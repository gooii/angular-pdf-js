class PdfService

  @$inject:    ['PdfPageRenderService','PdfPageTextService','$log']
  constructor: ( @renderService,        @textService,        @log) ->
    @log.log('PDF Service')

    @pageInfos = []
    @pageProxies = []

    @totalPages = 0
    @allPagesReady = false

  clear: () =>
    @renderService.clear()

  hasPdf: () =>
    return @pdf != null

  hasPageInfos: () =>
    return @pageInfos != null && @pageInfos.length > 0

  openPdf: (url) =>
    promise = PDFJS.getDocument(url)
    promise.then(@pdfLoaded, @pdfLoadError)
    return promise

  pdfLoaded: (pdf) =>
    @pdf = pdf
    @totalPages = pdf.numPages
    @textService.totalPages = @totalPages
    @createPageInfos()

  pdfLoadError: (error) =>
    @log.error 'Pdf Load Error %O', error

  createPageInfos: () =>
    @log.log('Create page infos')
    for i in [1..@totalPages] by 1
      @pageInfos[i-1] = {
        id:i
        uid:i
        number: i
        index: i - 1
        isOdd: i % 2 == 0
        hasData: false
      }

  fetchPageFromPdf: (pageNumber) =>
    @log.log('Fetch page from PDF %O number %s. numPages %s',@pdf, pageNumber, @totalPages)
    if pageNumber <= 0 or pageNumber > @totalPages
      @log.warn('Page out of bounds')
    else if not @pageProxies[pageNumber - 1]
      @log.log('Requesting PDF page')
      promise = @pdf.getPage(pageNumber)
      promise.then(@pageLoaded, @pageLoadError)
      return promise
    else
      @log.log('Ignoring page request')

  pageLoaded: (page) =>
    @pageInfos[page.pageNumber - 1].hasData = true
    @pageProxies[page.pageNumber - 1] = page
    if @pageProxies.length == @pageInfos.length
      @log.info('All pages ready')
      @allPagesReady = true

    @textService.extractPageText(page)

  pageLoadError: () =>

    # Get page by page number NOT PAGE INDEX
  getPageInfo: (number) =>
    @log.log('Get page %s %O', number, @pageInfos[number-1])
    return @pageInfos[number-1]

  # Get the original PDFPageProxy for the wrapper
  getPdfPageProxy: (pageInfo) =>
    @log.log('Get page source for %O (%s)', pageInfo, pageInfo.id)
    if @pageProxies[pageInfo.id - 1]
      return @pageProxies[pageInfo.id - 1]
    else
      @log.info('Page source not available, fetching page proxy from PDF. id: %s', pageInfo.id)
      return @fetchPageFromPdf(pageInfo.id)

  getProxyAtIndex: (index) =>
    return @pageProxies[index]

  getPdfPageProxyByNumber: (pageNumber) =>
    info = getPageInfo(pageNumber)
    proxy = getPdfPageProxy(info)
    return proxy

  destroy: () =>
    if @pdf
      @pdf.destroy()

  render: (number, canvas, size) =>
    return @renderService.render(number, canvas, size)

  renderPage: (pdfPage, viewport, canvas, textDiv) =>
    return @renderService.renderPage(pdfPage, viewport, canvas, textDiv)

  updateMatches: (query, matches) =>
    return @textService.updateMatches(query, matches)

app = angular.module 'angular-pdf-js'
app.service 'PdfService', PdfService
