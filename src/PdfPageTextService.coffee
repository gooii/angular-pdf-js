class PdfPageTextService

  @$inject: ['$log', '$q']

  constructor: (@log, @$q) ->
    @clear()

  clear: () =>
    # extract text from pages
    @textContent = []

    # the TextLayerBuilder objects for each page, used to update matches when doing page based search
    @textLayers = []

    @pendingText = []

    @totalPages = 0

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

  # Extract text from a PdfPageProxy
  # returns Promise
  extractPageText: (pdfPageProxy) =>
    @log.log('TEXT: Extract page text %s',pdfPageProxy.pageNumber)

    deferred = @$q.defer()

    pageIndex = ~~(pdfPageProxy.pageNumber - 1)
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
          @pendingText[pageIndex] = null
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
          @log.warn('Text extraction error')
        @pendingText[pageIndex] = deferred.promise

    return deferred.promise

app = angular.module 'angular-pdf-js'

app.service 'PdfPageTextService', PdfPageTextService
