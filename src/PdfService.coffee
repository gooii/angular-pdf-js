class PdfService

  @$inject:    ['PdfPageRenderService','PdfPageTextService','PdfHtmlUI','$log','$q']
  constructor: ( @renderService,        @textService,        @htmlUI,  @log, @$q) ->
    @log.log('PDF Service v3')

    @pageInfos = []
    @pageProxies = []

    @totalPages = 0
    @allPagesReady = false

    @htmlUI.model = @
    @renderService.model = @

  clear: () =>
    @renderService.clear()

  hasPdf: () =>
    return @pdf != null

  hasPageInfos: () =>
    return @pageInfos != null && @pageInfos.length > 0

  openPdf: (url) =>
    @loadPdfDeferred = @$q.defer()
    pdfDocumentProxy = PDFJS.getDocument(url)
    pdfDocumentProxy.then(@pdfLoaded, @pdfLoadError)
    return @loadPdfDeferred.promise

  pdfLoaded: (pdf) =>
    @log.log('SVC: Pdf Loaded %O',pdf)
    @pdf = pdf
    @totalPages = pdf.numPages
    @textService.totalPages = @totalPages
    # Model
    @createPageInfos()

    @loadPdfDeferred.resolve(@pdf)

  pdfLoadError: (error) =>
    @log.error 'SVC: Pdf Load Error %O', error
    @loadPdfDeferred.reject(@pdf)

  createPageInfos: () =>
    @log.log('SVC: Create page infos')
    for i in [1..@totalPages] by 1
      @pageInfos[i-1] = {
        id:i
        uid:i
        number: i
        index: i - 1
        isOdd: i % 2 == 0
        hasData: false
      }

  # Show a page by page number (1 based)
  # return Promise which resolves when the page has loaded (but not rendered)
  showPage: (pageNumber) =>
    @log.log('SVC: Show Page %s',pageNumber)
    if @pageInfos[pageNumber - 1].hasData
      @log.log('SVC: Page already has data. Scroll into view?')
    else
      return @fetchPageFromPdf(pageNumber)

  fetchPageFromPdf: (pageNumber) =>
    @log.log('SVC: Fetch page from PDF %O number %s. numPages %s',@pdf, pageNumber, @totalPages)
    if @pageProxies[pageNumber - 1]
      return @pageProxies[pageNumber - 1]
    else if pageNumber <= 0 or pageNumber > @totalPages
      @log.warn('SVC: Page out of bounds')
    else if not @pageProxies[pageNumber - 1]
      @log.log('SVC: Requesting PDF page')
      promise = @pdf.getPage(pageNumber)
      promise.then(@pageLoaded, @pageLoadError)
      return promise
    else
      @log.log('SVC: Ignoring page request')

  pageLoaded: (page) =>
    @log.log('SVC: Page Loaded %s %O', page.pageNumber, page)

    @pageInfos[page.pageNumber - 1].hasData = true
    @pageProxies[page.pageNumber - 1] = page
    if @pageProxies.length == @pageInfos.length
      @log.info('SVC: All pages ready')
      @allPagesReady = true

    renderJob = @renderWithText(page)
    @log.log('SVC: Render Job',renderJob)
    renderJob.promise.then @pageRendered, @pageRenderError

  pageRendered: (renderJob) =>
    @log.log('SVC: Page Rendered',renderJob)

  pageRenderError: (err) =>
    @log.warn('SVC: Page Render Error',err)

  pageLoadError: (err) =>
    @log.log('SVC: Page load error %O', err)

  pageLoadError: () =>
    @log.error 'SVC: Page load error'

    # Get page by page number NOT PAGE INDEX
  getPageInfo: (number) =>
    @log.log('SVC: Get page %s %O', number, @pageInfos[number-1])
    return @pageInfos[number-1]

  # Get the original PDFPageProxy for the wrapper
  getPdfPageProxy: (pageInfo) =>
    @log.log('SVC: Get page source for %O (%s)', pageInfo, pageInfo.id)
    if @pageProxies[pageInfo.id - 1]
      return @pageProxies[pageInfo.id - 1]
    else
      @log.info('SVC: Page source not available, fetching page proxy from PDF. id: %s', pageInfo.id)
      return @fetchPageFromPdf(pageInfo.id)

  getProxyAtIndex: (index) =>
    return @pageProxies[index]

  getPdfPageProxyByNumber: (pageNumber) =>
    info = @getPageInfo(pageNumber)
    proxy = @getPdfPageProxy(info)
    return proxy

  destroy: () =>
    @log.log('SVC: Destroy')
    if @pdf
      @pdf.destroy()

  render: (number, canvas, size) =>
    return @renderService.render(number, canvas, size)

  renderWithText: (pdfPage) =>
    @log.log('SVC: Render with text %s',pdfPage.pageNumber)
    renderConfig = @htmlUI.getRenderConfigForPage(pdfPage)
    return @renderService.renderPage(pdfPage, renderConfig)

  updateMatches: (query, matches) =>
    return @textService.updateMatches(query, matches)

app = angular.module 'angular-pdf-js'
app.service 'PdfService', PdfService
