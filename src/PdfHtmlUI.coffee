
class PdfHtmlUI

  @$inject: ['$document','$log']
  constructor: (@document, @log) ->
    @textLayerClass = 'textLayer'
    @pageContainerClass = 'pageContainer'
    @canvasClass = 'pdfPage'

    @currentZoom = 1

    @containerElement = null

    @pageContainers = []

  clear: () =>
    # TODO : Either clear the existing containers properly or re-use them
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
      @log.error('Container not found for page', pdfPage.pageNumber)
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

    return {wrapper:canvasWrapper, canvas:canvas, page:page, anchor:anchor, textLayer:textLayer[0]}

  calculateInitialViewport: (page) =>

    @log.log('UI: Calculate initial viewport')

    viewport = page.getViewport(1,0)
    @log.log('UI: Viewport %O',viewport)

    return viewport

    vw = viewport.width
    cw = @containerElement.width()

    @fitWidthScale = cw / vw
    @fitHeightScale = (@containerElement.height() - @containerElement.offset().top) / viewport.height

    # If viewport is wider than canvas then
    if vw > cw
      @log.log('UI: Using fit width scale')
      @currentZoom = @fitWidthScale
    else
      @log.log('UI: Using fit height scale')
      @currentZoom = @fitHeightScale

    @defaultZoom = @currentZoom

    @log.log('UI: Canvas Container %s, %s. Viewport %O',@containerElement.width(),@containerElement.height(), viewport)
    return page.getViewport(@currentZoom)

  scrollToPage: (page) =>
    @log.log('UI: Scroll to page %O', page)
    # scroll to named anchor
    config = @pageContainers[page.pageIndex]

    @log.log 'UI: Page config %O', config
    offset = config.anchor.offset()
    currentTop = @containerElement.scrollTop()
    containerOffset = @containerElement.offset().top
    #      @log.log('Scroll To %s %s %s', offset.top, currentTop, containerOffset)
    @containerElement.scrollTop(offset.top + currentTop - containerOffset)

app = angular.module 'angular-pdf-js'
app.service 'PdfHtmlUI', PdfHtmlUI
