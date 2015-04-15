# Render queue
class RenderJob
  # Job configuration

  # @property [PdfPageProxy]
  page:     null
  # @property [RenderContext] the context for the PDF.js rendering process
  context:  null
  # @property [Promise] the promise to use for notification of rendering completion or errors
  promise:  null
  # @property [deferred] the raw deferred object from $q, used internally
  deferred: null

  textDiv: null
  constructor: (@page, @context, @deferred) ->
    @promise = @deferred.promise

class PendingPage
  # Page info used to keep a record of pages that have been requested for rendering but for who the PdfPageProxy is not yet available
  # Once the proxy is available the page will be rendered automatically

  # @property [PageInfo] page info object from the Publication Model
  page:     null
  # @property [deferred] the deferred / promise object to use for completion and error notification
  deferred: null
  # @property [int] If the size is > 0 then this is used as the zoom factor when rendering, otherwise the factor is calculated
  # according to the canvas size so that the rendered page fits exactly within it
  size:     null
  # @property [Canvas] the canvas on which to render the page
  canvas:   null

  constructor: (@page, @deferred, @size, @canvas) ->

class PdfPageRenderService

  @RenderingStates:
    INITIAL: 0
    RUNNING: 1
    PAUSED: 2
    FINISHED: 3

  # Pages which aren't yet ready for rendering but have been requested
  pendingPages = []

  # Pages queued for rendering
  queue = []

  thumbCache = {}

  cache = []

  @$inject: [   '$q', '$log', '$timeout', 'PdfPageTextService']
  constructor: (@$q,   @log,  @$timeout,  @textService) ->
    @clear()

  clear: () =>
    @log.log('Render: Clear')

    @busy = false
    @pendingPages = []
    @queue = []
    @cache = []
    @thumbCache = {}

  # Request a single page to be rendered using the supplied viewport and canvas
  # @returns [RenderJob] a render job with a promise which is resolved when the page has been rendered
  renderPage: (page, renderConfig) =>

    @log.log('Render: Rendering page %O with config %O', page, renderConfig)
    # Check cache to see if page has been rendered

    if cache[page]
      @log.info('Render: Page exists in cache. Do something clever here')

    renderContext = {
      canvasContext: @createDrawingContext(renderConfig.canvas, renderConfig.viewport)
      viewport: renderConfig.viewport
    }

    deferred = @$q.defer()
    pageIndex = ~~(page.pageNumber - 1)
    renderJob = new RenderJob(page, renderContext, deferred)
    renderJob.textDiv = renderConfig.textLayer
    if @textService.textContent[pageIndex]
      @log.log('Render: Text content available for %s', pageIndex)
      return @addToQueue(renderJob)
    else
      @log.log('Render: Waiting for text %s', pageIndex)
      textPromise = @textService.extractPageText(page)
      t = _.partial(@textReady, renderJob)
      te = _.partial(@textError, renderJob)
      textPromise.then t, te

    return renderJob

  textError: (renderJob, textContent) =>
    @log.error('Render: Text error %O %O', renderJob, textContent)
    @addToQueue(renderJob)

  textReady: (renderJob, textContent) =>
    @log.log('Render: Text ready %O %O', renderJob, textContent)
    @addToQueue(renderJob)

  # Render a page based on its number (1 based) without a text layer.
  # Example call used by thumbnail directive
  # @pageRenderService.render(@page.id, @canvas, -1)
  # returns a promise
  render: (number, canvas, size) =>
    @log.log('Render: Render %s at %s onto %O', number,size,canvas)

    deferred = @$q.defer()

    # Get the page info model
    page = @model.getPageInfo(number)
    if not page
      @log.error('Render: Page not found in model')
      deferred.reject()
      return deferred

    # get the PDFPageProxy
    pdfPage = @model.getPdfPageProxy(page)

    if not pdfPage
      @log.error('Render: pdfPage doesnt exist %O', pdfPage)
      return
    else
      @log.log('Render: Page source %O. Page info %O', pdfPage, page)

    if page.hasData
      if @thumbCache[pdfPage.pageIndex]
        canvas.getContext('2d').putImageData(@thumbCache[pdfPage.pageIndex],0,0)
        deferred.resolve()
        return deferred

      # pdfPage is the actual PDFPageProxy
      @log.log('Render: Page has data, ready to render %s',number)

      # Check if any pending pages match
      pending = _.find @pendingPages, (item) =>
        @log.log('Render: Checking pending %O %O',item, pdfPage)
        return item.page.number == (pdfPage.pageIndex + 1)

      if pending
        @log.log('Render: Pending page matches %s', number)
        @pageReadyToRender(pdfPage)

      viewport = @createViewport(pdfPage, size, canvas)
      requested = @renderPage(pdfPage, viewport, canvas)

      return requested
    else
      # pdfPage is a promise
      @log.log('Render: Page doesnt have data, requesting data before rendering %s %O',number, pdfPage)
      @pendingPages.push(new PendingPage(page,deferred, size, canvas))
      tmp = @pendingPages.slice()
      @log.log('Render: Pending pages %O', tmp)
      pdfPage.then(@pageReadyToRender, @fetchPageError)
      return deferred

  pageReadyToRender: (pdfPageProxy) =>
    if not pdfPageProxy
      @log.error('Render: Page ready but proxy is missing')
      return

    @log.log('Render: Page ready to render %O %s', pdfPageProxy, pdfPageProxy.pageIndex)
    pending = _.find @pendingPages, (item) =>
      @log.log('Render: Checking pending %O %O',item, pdfPageProxy)
      return item.page.number == (pdfPageProxy.pageIndex + 1)

    if pending
      @pendingPages.splice(@pendingPages.indexOf(pending),1)

      @log.log('Render: Found pending %O', pending)
      # Now check if we've actually rendered the page in the meantime so we dont render it again

      viewport = @createViewport(pdfPageProxy, pending.size, pending.canvas)
      renderContext = {
        canvasContext: @createDrawingContext(pending.canvas, viewport),
        viewport: viewport
      }

      @log.log('Render: Pending pages now %O', @pendingPages)

      renderJob = new RenderJob(pdfPageProxy,renderContext,pending.deferred)
      @addToQueue(renderJob)
      return renderJob
    else
      @log.warn('Render: Page is ready but not pending %O %s', pdfPageProxy, pdfPageProxy.pageIndex)

  @fetchPageError: (res) =>
    @log.log('Render: Page render error')

  # Add a render job to the queue and return it
  #
  # @param    [RenderJob] the job to add to the queue :)
  # @returns  [RenderJob] the same thing you passed in
  addToQueue: (renderJob) =>

    if not @busy
      # Render now
      @doRenderJob(renderJob)
    else
      @queue.push(renderJob)

    return renderJob

  # Render a page according to the render job configuration
  #
  # Any jobs that remain on the queue after processing the current job will be processed after a small delay
  # triggered by the angular $timeout service
  #
  # @param  [RenderJob] the job configuration to use for rendering
  # @return [RenderJob] render job configuration
  doRenderJob: (job) =>

    if @busy
      @log.warn('Render: Renderer is busy')
      return

    @busy = true
    if not job and @queue.length > 0
      job = @queue.pop()

    @log.log('Render: DoRenderJob. Index %s Job %O', job.page.pageIndex, job)
    if job.textDiv
      if @textService.textContent[job.page.pageIndex]
        textContent = @textService.textContent[job.page.pageIndex]
        tlbOptions = {textLayerDiv:job.textDiv, pageIndex:job.page.pageIndex, viewport:job.context.viewport}
        @log.log('Render: TLB Options %O', tlbOptions)
        textLayer = new TextLayerBuilder(tlbOptions);
        @textService.textLayers[job.page.pageIndex] = textLayer
        @log.log('Render: Text Layer %O. Text content %O', textLayer, textContent)
        textLayer.setTextContent(textContent)
        job.context.textLayer = textLayer
      else
        @log.info 'Render: text content not available %s', job.page.pageIndex
    else
      @log.log('Render: Job has no text div target')

    @currentJob = job
    job.page.render(job.context).then @jobDone, @renderError
    return job

  jobDone: (res) =>
    @log.log('Render: Job Done %s %O', @currentJob.page.pageIndex, @currentJob)

    if not @currentJob.textDiv
      ctx = @currentJob.context.canvasContext
      @log.log('Render: Save thumb to cache %s %O', @currentJob.page.pageIndex, ctx)
      @thumbCache[@currentJob.page.pageIndex] = ctx.getImageData(0,0,ctx.canvas.width,ctx.canvas.height)
    @cache[@currentJob.page.pageIndex] = @currentJob
    @currentJob.deferred.resolve(@currentJob)
    @busy = false
    if @queue.length > 0
      @log.log('Render: Queue is not empty : %s', @queue.length)
      @$timeout @doRenderJob, 50

    return @currentJob

  renderError: (err) =>
    @log.error('Render: Render error %s', err)

  createDrawingContext: (canvas, viewport) =>
    ctx = canvas.getContext('2d')
    ctx.save()
    ctx.fillStyle = 'rgb(255, 255, 255)'
    ctx.fillRect(0, 0, viewport.width, viewport.height)
    ctx.restore()
    return ctx

  createViewport: (page, size, canvas) =>
    if size > 0
      return page.getViewport(size)

    zoom = 1
    viewport = page.getViewport(1)
    vw = viewport.width
    cw = canvas.width

    viewportAspectRatio = viewport.width / viewport.height
    renderAspectRatio = canvas.width / canvas.height

    fitWidthScale = cw / vw
    fitHeightScale = canvas.height / viewport.height

    if viewportAspectRatio > renderAspectRatio
      zoom = fitWidthScale
    else
      zoom = fitHeightScale

    return page.getViewport(zoom)

app = angular.module 'angular-pdf-js'
app.service 'PdfPageRenderService', PdfPageRenderService
