export default {
    data: () => ({
        toast: {
            text: '',
            color: 'success',
            timeout: 5000
        },
        notificationQueue: [],
        notification: false
    }),
    computed: {
        hasNotificationsPending () {
            return this.notificationQueue.length > 0
        }
    },
    watch: {
        notification () {
            if (!this.notification && this.hasNotificationsPending) {
                this.toast = this.notificationQueue.shift()
                this.$nextTick(() => { this.notification = true })
            }
        }
    },
    methods: {
        addNotification (toast) {
            if (typeof toast !== 'object') return
            this.notificationQueue.push(toast)

            if (!this.notification) {
                this.toast = this.notificationQueue.shift()
                this.notification = true
            }
        },
        makeToast (text, color = 'info', timeout = 6000, top = true, bottom = false, right = false, left = false, multiline = false, vertical = false) {
            return {
                text,
                color,
                timeout,
                top,
                bottom,
                right,
                left,
                multiline,
                vertical
            }
        }
    }
}