import Vue from 'vue'
import Toast from './Toast'

let queue = []
let showing = false

export { Toast }
export default {
    open(params) {
        if (!params.text) return console.error('[toast] no text supplied')
        if (!params.type) params.type = 'info'

        let propsData = {
            title: params.title,
            text: params.text,
            type: params.type
        }

        let defaultOptions = {
            color: params.type || 'info',
            closeable: true,
            autoHeight: true,
            timeout: 1000,
            multiLine: !!params.title || params.text.length > 80
        }

        params.options = Object.assign(defaultOptions, params.options)
        propsData.options = params.options

        // push into queue
        queue.push(propsData)
        processQueue()
    }
}

function processQueue() {
    if (queue.length < 1) return
    if (showing) return

    console.log(queue)

    let nextInLine = queue[0]
    spawn(nextInLine)
    showing = true

    queue.shift()
}

function spawn(propsData) {
    const ToastComponent = Vue.extend(Toast)
    return new ToastComponent({
        el: document.createElement('div'),
        propsData,
        onClose: function() {
            showing = false
            processQueue()
        }
    })
}