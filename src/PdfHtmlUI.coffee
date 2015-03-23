
class PdfHtmlUI

  @$inject: ['$document','$log']
  constructor: (@document, @log) ->
    @textLayerClass = 'textLayer'
    @pageContainerClass = 'pageContainer'
    @canvasClass = 'pdfPage'

  createContainer: (parent, page, viewport) =>

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

    context = canvas.getContext('2d')
    renderContext = {
      canvasContext: context,
    }

    return {wrapper:canvasWrapper, canvas:canvas, renderContext:renderContext, page:page, anchor:anchor, textLayer:textLayer[0]}

app = angular.module 'angular-pdf-js'
app.service 'PdfHtmlUI', PdfHtmlUI
