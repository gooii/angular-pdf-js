
class PdfHtmlUI

  @$inject: ['$document','$log']
  constructor: (@document, @log) ->
    @textLayerClass     = 'textLayer'
    @pageContainerClass = 'pageContainer'
    @canvasClass        = 'pdfPage'
    @currentZoom        = 1
    @containerElement   = null
    @pageHeight         = 0
    @scrollOffset       = 0
    @pageContainers     = []


    # performs the zoom based on @currentZoom value
    @_doZoom = _.throttle(
      ((visibleLimits, fnSetVisibleLimits) =>
        @log.warn "Throttled do zoom."
        @resizeContainers()
        @scrollChanged()
        if visibleLimits
          fnSetVisibleLimits(visibleLimits.first, visibleLimits.last))
      , 2000)

    # private zoom in function - we do not debounce/throttle
    # access so that the zoom level can be increased as many
    # times as the user clicks but we throttle the functions
    # that actually manipulate the DOM
    @_zi = (amount, visibleLimits, fnSetVisibleLimits) =>
      # adjust current zoom level
      amount        = amount || 0.1
      @currentZoom += amount
      # do the DOM
      @_doZoom(visibleLimits, fnSetVisibleLimits)

    # private zoom out function - we don't debounce/throttle
    # access so that the zoom level can be decreased as many
    # times as the user clicks but we throttle the functions
    # that actually manipulate the DOM
    @_zo = (amount, visibleLimits, fnSetVisibleLimits) =>
      # adjust current zoom level
      amount        = amount || 0.1
      @currentZoom -= amount
      # reset base zoom level if it drops below 0.1
      if @currentZoom < 0.1
        @currentZoom = 0.1
      # do the DOM
      @_doZoom(visibleLimits, fnSetVisibleLimits)

    # private reset zoom function
    @_rz = (visibleLimits, fnSetVisibleLimits) =>
      # bomb out if current zoom is already default zoom
      return if @currentZoom == @defaultZoom
      # reset back to default
      @currentZoom = @defaultZoom || 1
      # invoke throttle function
      @_doZoom(visibleLimits, fnSetVisibleLimits)

    # expose public functions which defer to the private functions
    # and guarantee that they won't be called more than once per n
    # milliseconds
    @zoomIn    = @_zi
    @zoomOut   = @_zo
    @resetZoom = @_rz

  setup: (@model, @renderService) =>
    @log.log('UI: Setup HtmlUI')

  setContainer: (@containerElement, @scrollElement) =>
    @log.log('UI: Set Container Element',@containerElement)
    if @containerElement.length > 0
      @containerFirstItem = @containerElement[0]
    else
      @log.error('UI: Expected Jquery element')

    @visibleHeight = @containerElement.parent().height()

    @log.log('UI: setContainer',@containerFirstItem.getBoundingClientRect(), @visibleHeight)

    @watchScroll(@scrollElement, @scrollChanged)

  scrollChanged: (event) =>
    scrollPosTop = @containerElement.scrollTop()

    @log.log('UI: Scroll',scrollPosTop, @pageHeight, @visibleHeight)
    if @pageHeight
      topPage = scrollPosTop / @pageHeight
      bottomPage = (scrollPosTop + @visibleHeight) / @pageHeight

      topVisiblePage = Math.floor(topPage)
      bottomVisiblePage = Math.floor(bottomPage)
      @log.log('UI: Page : ',topVisiblePage, bottomVisiblePage)

      @model.setVisibleLimits(topVisiblePage, bottomVisiblePage)
    # event has lastY and down (i.e. scroll direction) properties
    # Work out which pages are currently visible

  clear: () =>
    @currentZoom = 1
    if @containerElement
      @containerElement.empty()
    @pageContainers = []

  createUI: () =>
    @log.log('UI: Create UI. Size : %s, %s', @containerElement.width(), @containerElement.height())
    if @model.pdf.numPages > 0
      pageProxy = @model.getPdfPage(0)
      # If the page is ready it has a pageIndex, otherwise its a promise
      if pageProxy.pageIndex
        createViews(pageProxy)
      else
        pageProxy.then @createViews, @pdfError

  pdfError: (err) =>
    @log.error('UI: PDF Error in HTML UI')

  getRenderConfigForPage: (pdfPage) =>
    @log.log('UI: Get render config for page %O',pdfPage, pdfPage.pageNumber)
    if @pageContainers.length == 0
      @log.log('UI: No Containers creating views')
      container = @createViews(pdfPage)
    else
      container = @pageContainers[pdfPage.pageNumber - 1]

    if not container
      @log.error('UI: Container not found for page', pdfPage.pageNumber)
      throw "Container not found"

    viewport = pdfPage.getViewport(@currentZoom)
    # Compare viewport width with canvas width
    if Math.floor(viewport.width) > container.canvas.width
      @log.warn('Viewport width is bigger than canvas', viewport.width, container.canvas.width)
      newZoom = @currentZoom * (container.canvas.width / viewport.width)
      viewport = pdfPage.getViewport(newZoom)

    container.viewport = viewport
    return container

  createViews: (pdfPageProxy) =>

    @log.log('UI: Create Views %O %s, %s', pdfPageProxy, @containerElement.width(), @containerElement.height())

    @firstPageProxy = pdfPageProxy

    viewport = @calculateInitialViewport(pdfPageProxy)

    @log.log('UI: Initial viewport %O',viewport)

    for pageNumber in [1..@model.pdf.numPages] by 1
      @log.log('UI: Creating page container %s', pageNumber)
      container = @createPageContainer(@containerElement, @model.getPageInfo(pageNumber-1), viewport)
      @pageContainers.push(container)

    @log.log('UI: Created page containers', @pageContainers)

    @pageContainers[0].pdfPage = pdfPageProxy
    @pageRect = @pageContainers[0].canvas.getBoundingClientRect()
    @log.log('UI: Page Rect',@pageRect)

    if @pageContainers.length > 1
      @scrollOffset = @pageRect.top
      @pageHeight = @pageContainers[1].canvas.getBoundingClientRect().top - @scrollOffset
      @log.log('UI: Scroll Offset %s Page Height %s',@scrollOffset, @pageHeight)
      @scrollChanged()

    return @pageContainers[0]

  createPageContainer: (parent, pageInfo, viewport) =>
    @log.log('UI: Create page container %O %O %O',parent, pageInfo, viewport)
    anchor = angular.element('<a></a>')
    anchor.attr('name', 'page' + pageInfo.id)

    canvasWrapper = angular.element('<div></div>')
    canvasWrapper.attr('id', 'pageContainer' + pageInfo.id)

    canvasWrapper.css('width',viewport.width)
    canvasWrapper.css('height',viewport.height)
    canvasWrapper.attr('class',@pageContainerClass)

    canvas = document.createElement('canvas')

    canvas.id = 'page' + pageInfo.id
    canvas.width = viewport.width
    canvas.height = viewport.height
    canvas.className = @canvasClass

    textLayer = angular.element('<div class="' + @textLayerClass + '"></div>')
    canvasWrapper.append(canvas)
    canvasWrapper.append(textLayer)

    parent.append(anchor)
    parent.append(canvasWrapper)

    # TODO : Work out all that nonsense with position relative / absolute etc..
    loadingIconDiv = angular.element('<div class="loadingIcon"></div>')
#    canvasWrapper.append(loadingIconDiv)

    return {wrapper:canvasWrapper, canvas:canvas, page:pageInfo, anchor:anchor, textLayer:textLayer[0], text:true, loadingIcon:loadingIconDiv}

  removeLoadingIcon: (renderJob) =>
    container = @pageContainers[renderJob.page.pageIndex]
    @log.log('UI: Remove loading icon',renderJob, container)
    if container and container.loadingIcon
      container.loadingIcon.remove()

  calculateInitialViewport: (page) =>

    @log.log('UI: Calculate initial viewport')

    viewport = page.getViewport(@currentZoom,0)
    @log.log('UI: Viewport %O',viewport)

    vw = viewport.width
    # Leave some space either side
    cw = @containerElement.width() - 32

    @log.log('UI: VW %s CW %s',vw, cw)

    if cw <= 0
      @currentZoom = 1
    else
      @fitWidthScale = cw / vw
      @currentZoom = @fitWidthScale

    @defaultZoom = @currentZoom

    @log.log('UI: Canvas Container %s, %s. Viewport %O',@containerElement.width(),@containerElement.height(), viewport)
    return page.getViewport(@currentZoom, 0)

  scrollTo: (pageIndex) =>
    @log.log('UI: Scroll to page %O', pageIndex)
    # scroll to named anchor
    config = @pageContainers[pageIndex]

    @log.log 'UI: Page config %O', config
    offset = config.anchor.offset()
    currentTop = @scrollElement.scrollTop()
    @log.log('Scroll To %s %s %s', offset.top, currentTop, @scrollOffset)
    @scrollElement.scrollTop(offset.top + currentTop - @scrollOffset)

  scrollToPage: (page) =>
    @scrollTo(page.pageIndex)

  # Adapted from PDF.js source
  # Helper function to start monitoring the scroll event and converting them into
  # PDF.js friendly one: with scroll debounce and scroll direction.
  watchScroll: (viewAreaElement, callback) =>
    @log.log('UI: Watch Scroll',viewAreaElement)
    debounceScroll = (evt) =>
      if (rAF)
        return

      # schedule an invocation of scroll for next animation frame.
      rAF = window.requestAnimationFrame () =>
        rAF = null;

        currentY = viewAreaElement.scrollTop();
        lastY = state.lastY;
        if currentY != lastY
          state.down = currentY > lastY

        state.lastY = currentY
        callback(state)

    state = {
      down: true
      lastY: viewAreaElement.scrollTop()
      _eventHandler: debounceScroll
    }

    rAF = null
    viewAreaElement.on('scroll', debounceScroll)
    return state

  resizeContainers:() =>
    @log.warn "Resizing containers."
    # check we have at least one page container
    return if @pageContainers.length < 1
    # resize
    viewport  = @firstPageProxy.getViewport(@currentZoom, 0)
    scrTop    = @containerElement.scrollTop()
    pgeTop    = @pageContainers[0]?.canvas.getBoundingClientRect().top

    @log.log('UI: Resize containers. Zoom %s, Viewport %O',@currentZoom, viewport)

    _.each @pageContainers, (p) =>
      p.wrapper.css('width',viewport.width)
      p.wrapper.css('height',viewport.height)
      p.canvas.width = viewport.width
      p.canvas.height = viewport.height

    @pageHeight = (scrTop + pgeTop) - @scrollOffset

    @log.log('UI: Page Height', @pageHeight, scrTop, @pageContainers[0]?.canvas.getBoundingClientRect())

    if @pageHeight < 0
      @log.error('Page height is less than zero. Something went wrong')
      @pageHeight = viewport.height

app = angular.module 'angular-pdf-js'
app.service 'PdfHtmlUI', PdfHtmlUI
