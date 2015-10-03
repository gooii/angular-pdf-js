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

  # Jobs queued for rendering. This is a priority queue, jobs at the front
  # get processed first
  queue = []

  # Jobs queued for rendering that are waiting for text content extraction
  # This is a map from pageIndex to renderJob
  textQueue = {}

  # Cache of completed render jobs with text layers
  cache = []
  # Cache of completed render jobs without text layers
  cacheWithoutText = []

  @$inject: [   '$q', '$log', '$timeout', 'PdfPageTextService']
  constructor: (@$q,   @log,  @$timeout,  @textService) ->
    @clear()

  clear: () =>
    @log.log('Render: Clear')

    # TextLayerBuilder objects used for rendering the text and search highlights
    @textLayers = []

    @busy = false
    @pendingPages = []
    @queue = []
    @textQueue = {}
    @cache = []
    @cacheWithoutText = []

  # Request a single page to be rendered using the supplied viewport and canvas
  # @returns [RenderJob] a render job with a promise which is resolved when the page has been rendered
  renderPage: (page, renderConfig) =>

    @log.log('Render: Rendering page %O with config %O', page, renderConfig)

    cacheItem = @checkCache(page, renderConfig)

    if cacheItem
      return cacheItem

    # Check if job is in the queue
    if @queue.length > 0
      @log.log('Render: checking queue',@queue, _.map(@queue,'page.pageIndex'))
      jobInQueue = null
      _.forEach @queue, (job) =>
        if (job.page == page) && (job.context.viewport.scale == renderConfig.viewport.scale)
          @log.log('Render: Matching job found in queue')
          jobInQueue = job
          return false
        else
          return true
      if jobInQueue
        return jobInQueue

    # Check if job is currently being rendered
    if @currentJob && (@currentJob.page == page) && (@currentJob.context.viewport.scale == renderConfig.viewport.scale)
      @log.log('Render: Current job matches request')
      return @currentJob

    # Create new render job
    renderJob = @createJob(page, renderConfig)

    # Does this job need a text layer render?
    if renderConfig.text
      # Check if the job is already waiting for text content
      job = @textQueue[page.pageIndex]
      if job && (job.page == page) && (job.context.viewport.scale == renderConfig.viewport.scale)
        @log.log('Render: Matching job found in text queue',@textQueue)
        return job

      # Check if the text content has been requested externally
      textPromise = @textService.isWaitingFor(page)
      @log.log('Render: Text Promise',textPromise)

      if not textPromise
        # Text content hasn't been requested yet so request it before rendering
        @log.log('Render: Request text before rendering',page.pageIndex)
        textPromise = @textService.extractPageText(page)

      t = _.partial(@textReady, renderJob)
      te = _.partial(@textError, renderJob)
      textPromise.then t, te

      # store job in the text queue
      @textQueue[page.pageIndex] = renderJob
      @log.log('Stored job in text queue',@textQueue)
      return renderJob

    @addToQueue(renderJob)
    return renderJob

  createJob: (page, renderConfig) =>
    renderContext = {
      canvasContext: @createDrawingContext(renderConfig.canvas, renderConfig.viewport)
      viewport: renderConfig.viewport
    }

    deferred = @$q.defer()
    renderJob = new RenderJob(page, renderContext, deferred)

    if renderConfig.text
      renderJob.textDiv = renderConfig.textLayer

    return renderJob

  checkCache: (page, renderConfig) =>
    # At the moment there are 2 caches, one for pages with text layers
    # and one for pages without (i.e. thumbnails)
    cache = if renderConfig.text then @cache else @cacheWithoutText

    if renderConfig.text
      @log.log('Render: Checking text cache',cache)
    else
      @log.log('Render: Checking cache',cache)

    if cache[page.pageIndex]
      cachedPage = cache[page.pageIndex]
      @log.info('Render: Page exists in cache.', cachedPage)
      # Checked cached render is the same resolution as the request
      if cachedPage.context.viewport.scale == renderConfig.viewport.scale
        return cachedPage
      else
        @log.log('Render: Cached page has different resolution')

  textError: (renderJob, textContent) =>
    @log.error('Render: Text error %O %O', renderJob, textContent)
    renderJob.textDiv = null
    renderJob.text = false
    @textQueue[renderJob.page.pageIndex] = null
    @addToQueue(renderJob)

  textReady: (renderJob, textContent) =>
    @log.log('Render: Text ready %O %O', renderJob, textContent)
    @textQueue[renderJob.page.pageIndex] = null
    @addToQueue(renderJob)

  # Add a render job to the queue and return it
  #
  # @param    [RenderJob] the job to add to the queue :)
  # @returns  [RenderJob] the same thing you passed in
  addToQueue: (renderJob) =>

    if not @busy
      # Render now
      @doRenderJob(renderJob)
    else
      # Prioritise renders with text layers
      if renderJob.textDiv
        @queue.unshift(renderJob)
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
      job = @queue.shift()

    @currentJob = job
    pageIndex = @currentJob.page.pageIndex

    @log.log('Render: DoRenderJob. Index %s Job %O', pageIndex, @currentJob)
    if @currentJob.textDiv
      if @textService.textContent[pageIndex]
        textContent = @textService.textContent[pageIndex]
        tlbOptions = {textLayerDiv:@currentJob.textDiv, pageIndex:pageIndex, viewport:@currentJob.context.viewport}
        @log.log('Render: TLB Options %O', tlbOptions)
        textLayer = new TextLayerBuilder(tlbOptions);
        @textLayers[pageIndex] = textLayer
        @log.log('Render: Text Layer %O. Text content %O', textLayer, textContent)
        textLayer.setTextContent(textContent)
        @currentJob.context.textLayer = textLayer
      else
        @log.info 'Render: text content not available %s', pageIndex
    else
      @log.log('Render: Job has no text div target')

    @currentJob.page.render(@currentJob.context).then @jobDone, @renderError
    return @currentJob

  jobDone: (res) =>
    @log.log('Render: Job Done %s %O', @currentJob.page.pageIndex, @currentJob)

    if not @currentJob.textDiv
      ctx = @currentJob.context.canvasContext
      @log.log('Render: Save thumb to cache %s %O', @currentJob.page.pageIndex, ctx)
      # Store the actual image data in the cache
      @currentJob.imageData = ctx.getImageData(0,0,ctx.canvas.width,ctx.canvas.height)
      @cacheWithoutText[@currentJob.page.pageIndex] = @currentJob
    else
      while @currentJob.textDiv.firstChild
        @currentJob.textDiv.removeChild(@currentJob.textDiv.firstChild)
        
      @currentJob.context.textLayer.render()
      @cache[@currentJob.page.pageIndex] = @currentJob

    @currentJob.deferred.resolve(@currentJob)

    @finishJob()

  renderError: (err) =>
    @log.error('Render: Render error %s', err)
    @currentJob.deferred.reject(@currentJob)
    @finishJob()

  finishJob: () =>
    @busy = false
    if @queue.length > 0
      @log.log('Render: Queue is not empty : %s', @queue.length, _.map(@queue,'page.pageIndex'))
      @$timeout @doRenderJob, 10

    completed = @currentJob
    @currentJob = null
    return completed

  cancelJob: (job) =>
    @log.log('Render: Cancel job',job)
    if @currentJob == job
      @log.log('Render: not cancelling current job')
    else if @queue.length and (@queue.indexOf(job) > -1)
      prevLength = @queue.length
      _.remove(@queue,job)
      @log.log('Render: remove job from queue', prevLength, queue.length)

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

  highlightText: (query, matches) =>
    @log.log('TEXT: Show matches', matches, @textLayers)
    _.each @textLayers, (textLayer) =>
      if textLayer
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
app.service 'PdfPageRenderService', PdfPageRenderService
