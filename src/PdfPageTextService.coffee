class PdfPageTextService

  charactersToNormalize: {
    '\u2018': '\'', # Left single quotation mark
    '\u2019': '\'', # Right single quotation mark
    '\u201A': '\'', # Single low-9 quotation mark
    '\u201B': '\'', # Single high-reversed-9 quotation mark
    '\u201C': '"',  # Left double quotation mark
    '\u201D': '"',  # Right double quotation mark
    '\u201E': '"',  # Double low-9 quotation mark
    '\u201F': '"',  # Double high-reversed-9 quotation mark
    '\u00BC': '1/4',# Vulgar fraction one quarter
    '\u00BD': '1/2',# Vulgar fraction one half
    '\u00BE': '3/4' # Vulgar fraction three quarters
  }

  @$inject: ['$log', '$q']

  constructor: (@log, @$q) ->
    replace = Object.keys(this.charactersToNormalize).join('')
    @normalizationRegex = new RegExp('[' + replace + ']', 'g')
    @clear()

  clear: () =>

    @textContentReady = false

    # extract text from pages
    @textContent = []

    # the TextLayerBuilder objects for each page, used to update matches when doing page based search
    @textLayers = []

    @pendingText = {}

    @pageContents = []

    @totalPages = 0

  normalize: (text) =>
    return text.replace @normalizationRegex, (ch) =>
      return @charactersToNormalize[ch]

  updateMatches: (query, matches) =>
    @log.log('TEXT: Update matches %O %O', matches, @textLayers)
    _.each @textLayers, (textLayer, index) =>
      findController = {
        active:true
        selected:
          pageIdx:textLayer.pageIdx
        state:
          query:query
          highlightAll:true
        pageMatches:matches
      }
      textLayer.findController = findController
      textLayer.updateMatches()

  # Has this page been queued for text extraction?
  isWaitingFor: (pdfPageProxy) =>
    return @pendingText[pdfPageProxy.pageIndex]

  # Extract text from a PdfPageProxy
  # returns Promise
  extractPageText: (pdfPageProxy) =>
    @log.log('TEXT: Extract page text %s',pdfPageProxy.pageNumber)

    deferred = @$q.defer()

    pageIndex = pdfPageProxy.pageIndex
    if not @textContent[pageIndex]
      if @pendingText[pageIndex]
        # if we are already waiting for the text
        @log.log('TEXT: Already waiting for text from page %s, %O', pageIndex, @pendingText[pageIndex])
        return @pendingText[pageIndex]
      else
        textPromise = pdfPageProxy.getTextContent()

        textPromise.then (textContent) =>
          @log.log('TEXT: Extracted page text %s %O', pageIndex,textContent)
          @textContent[pageIndex] = textContent
          strings = (item.str for item in textContent.items)
          @pageContents[pageIndex] = @normalize(strings.join('').toLowerCase())

          #@pendingText[pageIndex] = null
          # Count how many pages have been completed.
          # Because text may not be extracted in order
          # the @textContent array is scanned for non-null entries.
          completedText = 0
          _.each @textContent, (t) =>
            if t
              completedText++
          if completedText == @totalPages
            @log.log('TEXT: All text extracted')
            @textContentReady = true
          else
            @log.log('TEXT: Completed %s of %s', completedText, @totalPages)


          @log.log('TEXT: Resolve deferred')

          deferred.resolve({text:textContent, page:pdfPageProxy})
          return textContent

        , (error) =>
          deferred.reject({error:'Text extraction error',page:pdfPageProxy})
          @log.warn('TEXT: Text extraction error')
        @pendingText[pageIndex] = deferred.promise

    return deferred.promise


  find: (query) =>
    @log.log('TEXT: Search PDF Text %s', query)
    searchDeferred = @$q.defer()
    @doSearch(query, searchDeferred)
    return searchDeferred.promise

  doSearch: (query, deferred) =>
    @log.log('TEXT: Do Search',query, @pageContents)

    # array of page matches, where each entry is a list of substring indices
    matches = []
    # array of page results, where each entry is a list of strings
    results = []

    query = @normalize(query.toLowerCase())
    queryLen = query.length

    if (queryLen == 0)
      deferred.resolve({matches:matches,results:results})
      return deferred.promise

    _.map @pageContents, (contents, index) =>
      matches[index] = []
      matchIdx = -queryLen;
      while (true)
        matchIdx = contents.indexOf(query, matchIdx + queryLen)
        if (matchIdx == -1)
          break
        else
          @log.log('TEXT: Match index %s', matchIdx)
          matches[index].push(matchIdx)
          lastSpaceIndex = contents.substring(0,matchIdx).lastIndexOf(" ")
          results.push({id:index,number:index+1,text:contents.substr(lastSpaceIndex,200)})
          @log.log('TEXT: Match list %O', matches[index])

    @log.log('TEXT: Found matches %O', matches)
    @log.log('TEXT: Results %O', @results)
    @showMatches(query, matches)
    deferred.resolve({matches:matches,results:results})
    return deferred.promise

  showMatches: (query, matches) =>
    @log.log('TEXT: Show matches', matches, @textLayers)
    _.each @textLayers, (textLayer) =>
      textLayer.findController = {
        active:true
        selected:
          pageIdx:textLayer.pageIdx
        state:
          query:query
          highlightAll:true
        pageMatches:matches
      }
      textLayer.updateMatches()

app = angular.module 'angular-pdf-js'

app.service 'PdfPageTextService', PdfPageTextService
