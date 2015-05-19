
class PdfHtmlUI

  @$inject: ['$document','$log']
  constructor: (@document, @log) ->
    @textLayerClass = 'textLayer'
    @pageContainerClass = 'pageContainer'
    @canvasClass = 'pdfPage'

    @currentZoom = 1

    @containerElement = null

    @pageHeight = 0
    @scrollOffset = 0
    @pageContainers = []

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
    # TODO : Either clear the existing containers properly or re-use them
    @currentZoom = 1
    if @containerElement
      @containerElement.empty()
    @pageContainers = []

  createUI: () =>
    @log.log('UI: Create UI. Size : %s, %s', @containerElement.width(), @containerElement.height())
    if @model.pdf.numPages > 0
      pageProxy = @model.getPdfPageProxyByNumber(1)
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

    container.viewport = pdfPage.getViewport(@currentZoom)
    return container

  createViews: (pdfPageProxy) =>

    @log.log('UI: Create Views %O %s, %s', pdfPageProxy, @containerElement.width(), @containerElement.height())

    viewport = @calculateInitialViewport(pdfPageProxy)

    @log.log('UI: Initial viewport %O',viewport)

    for pageIndex in [1..@model.pdf.numPages] by 1
      @log.log('UI: Creating page container %s', pageIndex)
      container = @createPageContainer(@containerElement, @model.getPageInfo(pageIndex), viewport)
      @pageContainers.push(container)

    @log.log('UI: Created page containers', @pageContainers)

    @pageContainers[0].pdfPage = pdfPageProxy
    @pageRect = @pageContainers[0].canvas.getBoundingClientRect()
    @log.log('UI: Page Rect',@pageRect)

    if @pageContainers.length > 1
      @scrollOffset = @pageRect.top
      @pageHeight = @pageContainers[1].canvas.getBoundingClientRect().top - @scrollOffset
      @log.log('UI: Scroll Offset %s Page Height %s',@scrollOffset, @pageHeight)

    return @pageContainers[0]

  createPageContainer: (parent, page, viewport) =>
    @log.log('UI: Create page container %O %O %O',parent, page, viewport)
    anchor = angular.element('<a></a>')
    anchor.attr('name', 'page' + page.id)

    canvasWrapper = angular.element('<div></div>')
    canvasWrapper.attr('id', 'pageContainer' + page.id)

    canvasWrapper.css('width',viewport.width)
    canvasWrapper.css('height',viewport.height)
    canvasWrapper.attr('class',@pageContainerClass)

    canvas = document.createElement('canvas')

    canvas.id = 'page' + page.id
    canvas.width = viewport.width
    canvas.height = viewport.height
    canvas.className = @canvasClass

    textLayer = angular.element('<div class="' + @textLayerClass + '"></div>')
    canvasWrapper.append(canvas)
    canvasWrapper.append(textLayer)

    parent.append(anchor)
    parent.append(canvasWrapper)

    return {wrapper:canvasWrapper, canvas:canvas, page:page, anchor:anchor, textLayer:textLayer[0], text:true}

  calculateInitialViewport: (page) =>

    @log.log('UI: Calculate initial viewport')

    viewport = page.getViewport(1,0)
    @log.log('UI: Viewport %O',viewport)

    vw = viewport.width
    # Leave some space either side
    cw = @containerElement.width() - 32

    @log.log('UI: VW %s CW %s',vw, cw)

    @fitWidthScale = cw / vw
    @currentZoom = @fitWidthScale
    @defaultZoom = @currentZoom

    @log.log('UI: Canvas Container %s, %s. Viewport %O',@containerElement.width(),@containerElement.height(), viewport)
    return page.getViewport(@currentZoom)

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


app = angular.module 'angular-pdf-js'
app.service 'PdfHtmlUI', PdfHtmlUI
