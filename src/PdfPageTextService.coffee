class PdfPageTextService

  @$inject: ['$log']

  constructor: (@log) ->
    # extract text from pages
    @textContent = []

    # the TextLayerBuilder objects for each page, used to update matches when doing page based search
    @textLayers = []

    @pendingText = []

    @totalPages = 0

  updateMatches: (query, matches) =>
    @log.log('Update matches %O %O', matches, @textLayers)
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
    @log.log('Extract page text %s',pdfPageProxy.pageNumber)
    pageIndex = ~~(pdfPageProxy.pageNumber - 1)
    if not @textContent[pageIndex]
      if @pendingText[pageIndex]
        # if we are already waiting for the text
        @log.log('Already waiting for text from page %s, %O', pageIndex, @pendingText[pageIndex])
        return @pendingText[pageIndex]
      else
        textPromise = @pages[pageIndex].getTextContent()
        textPromise.then (textContent) =>
          @log.log('Extracted page text %s %O', pageIndex,textContent)
          @textContent[pageIndex] = textContent
          @pendingText[pageIndex] = null
          completedText = 0
          _.each @textContent, (t) =>
            if t
              completedText++
          if completedText == @totalPages
            @log.log('All text extracted')
            @textContentReady = true
          else
            @log.log('Completed %s of %s', completedText, @totalPages)
          return textContent
        , (error) =>
          @log.warn('Text extraction error')
        @pendingText[pageIndex] = textPromise
        return textPromise

app = angular.module 'angular-pdf-js'

app.service 'PdfPageTextService', PdfPageTextService
