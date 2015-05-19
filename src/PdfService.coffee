class PdfService

  @$inject:    ['PdfPageRenderService','PdfPageTextService','PdfHtmlUI','$log','$q']
  constructor: ( @renderService,        @textService,        @htmlUI,  @log, @$q) ->
    @log.log('PDF Service v3')

    @clear()

    @renderService.model = @
    @htmlUI.setup(@, @renderService)

  clear: () =>
    @log.info('Clear PDF Service')
    @pageInfos = []
    @pageProxies = []

    @currentPage = 0
    @totalPages = 0
    @allPagesReady = false
    @renderOnLoad = false

    @renderService.clear()
    @htmlUI.clear()
    @textService.clear()

  hasPdf: () =>
    return @pdf != null

  hasPageInfos: () =>
    return @pageInfos != null && @pageInfos.length > 0

  openPdf: (url) =>
    @log.log('Open PDF',url)
    @clear()
    @loadPdfDeferred = @$q.defer()
    @log.log('PDFJS getDocument')
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

  showPage: (pageNumber) =>
    @log.log('SVC: Show Page',pageNumber)
    pageIndex = pageNumber - 1
    if not @pageProxies[pageIndex]
      @log.warn('SVC: Page not loaded from PDF',pageNumber)
    else
      deferred = @renderWithText(@pageProxies[pageIndex])
      if deferred
        return deferred.promise
      else
        @log.log('SVC: renderWithText didnt return a promise', deferred)

  scrollTo: (pageIndex) =>
    @log.log('SVC: Scroll To',pageIndex)
    @htmlUI.scrollTo(pageIndex)

  # 0 based page indices for which pages are currently visible
  setVisibleLimits: (firstPage, lastPage) =>
    @log.log('SVC: Set visible limits',firstPage, lastPage)
    if lastPage > @pageProxies.length - 1
      lastPage = @pageProxies.length - 1
    for pageIndex in [firstPage..lastPage]
      @renderWithText(@pageProxies[pageIndex])

  # Load a page by page number (1 based)
  # return Promise which resolves when the page has loaded (but not rendered)
  loadPage: (pageIndex) =>
    @log.log('SVC: Load Page %s',pageIndex)
    if @pageInfos[pageIndex].hasData
      @log.log('SVC: Page already has data. Scroll into view?')
    else
      return @fetchPageFromPdf(pageIndex)

  # Retrieve all Page Proxies from the PDF document
  loadAllPages: () =>
    @loadPromise = @$q.defer()
    @log.log('SVC: Load All Pages',@allPagesReady)
    if !@allPagesReady and @currentPage == 0
      @loadNext()
    else
      @log.log('SVC: Not loading all pages, probably loading right now')

    return @loadPromise.promise

  loadNext: () =>
    @log.log('SVC: Load Next',@currentPage, @allPagesReady)
    if !@allPagesReady
      @loadPage(@currentPage++).then @loadNext
    else
      @loadPromise.resolve()

  fetchPageFromPdf: (pageIndex) =>
    @log.log('SVC: Fetch page from PDF %O index %s. numPages %s',@pdf, pageIndex, @totalPages)
    if @pageProxies[pageIndex]
      return @pageProxies[pageIndex]
    else if pageIndex < 0 or pageIndex > @totalPages
      @log.warn('SVC: Page out of bounds')
    else if not @pageProxies[pageIndex]
      @log.log('SVC: Requesting PDF page')
      promise = @pdf.getPage(pageIndex + 1)
      promise.then(@pageLoaded, @pageLoadError)
      return promise
    else
      @log.log('SVC: Ignoring page request')

  pageLoaded: (page) =>
    @log.log('SVC: Page Loaded %s %O', page.pageIndex, page)

    @pageInfos[page.pageIndex].hasData = true
    @pageProxies[page.pageIndex] = page
    if @pageProxies.length == @pageInfos.length
      @log.info('SVC: All pages ready')
      @allPagesReady = true

    if @renderOnLoad
      renderJob = @renderWithText(page)
      @log.log('SVC: Render Job',renderJob)
      renderJob.promise.then @pageRendered, @pageRenderError
    else
      @log.log('Not rendering page on load : ',page.pageIndex)

  pageRendered: (renderJob) =>
    @log.log('SVC: Page Rendered',renderJob)

  pageRenderError: (err) =>
    @log.warn('SVC: Page Render Error',err)

  pageLoadError: (err) =>
    @log.log('SVC: Page load error %O', err)

  pageLoadError: () =>
    @log.error 'SVC: Page load error'

  getPageInfo: (index) =>
    return @pageInfos[index]

  getPdfPage: (pageIndex) =>
    if @pageProxies[pageIndex]
      return @pageProxies[pageIndex]
    else
      @log.warn('Proxy not available',pageIndex)

  destroy: () =>
    @log.log('SVC: Destroy')
    if @pdf
      @pdf.destroy()

  # Render a page onto a canvas with the given size
  # If size is -1 then the page will be rendered to fit the canvas
  render: (number, canvas, size) =>
    @log.log('SVC: Render',number,canvas,size)
    pdfPage = @pageProxies[number - 1]
    if pdfPage
      renderConfig = {canvas:canvas,page:pdfPage,viewport:@renderService.createViewport(pdfPage, size, canvas),text:false}
      return @renderService.renderPage(pdfPage, renderConfig)
    else
      @log.warn('SVC: Cant render without page proxy',number)

  renderWithText: (pdfPage) =>
    @log.log('SVC: Render with text %s',pdfPage.pageIndex)
    renderConfig = @htmlUI.getRenderConfigForPage(pdfPage)
    renderJob = @renderService.renderPage(pdfPage, renderConfig)
    renderJob.promise.then @removeLoadingIcon
    return renderJob

  removeLoadingIcon: (renderJob) =>
    @htmlUI.removeLoadingIcon(renderJob)

  cancel: (renderJob) =>
    @log.log('SVC: Cancel render job',renderJob)
    @renderService.cancelJob(renderJob)

  updateMatches: (query, matches) =>
    return @textService.updateMatches(query, matches)

  loadAllText: () =>
    if !@textService.textContentReady
      @log.log('SVC: load all text')
      textPromises = _.map @pageProxies, (page) =>
        @textService.extractPageText(page)
      allTextPromise = @$q.all(textPromises)
      allTextPromise.then @textExtracted
      return allTextPromise
    else
      @log.info('SVC: All text extracted')

  textExtracted: () =>
    @log.log('SVC: All text extracted')

  find: (text) =>
    @log.log('SVC: Find',text)
    return @textService.find(text)

app = angular.module 'angular-pdf-js'
app.service 'PdfService', PdfService
