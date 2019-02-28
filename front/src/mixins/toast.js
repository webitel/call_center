export default {
    data: () => ({
    }),
    computed: {
        notificationQueue() {
            return this.$store.getters.notificationQueue;
        },
        toast() {
            return this.$store.getters.toast;
        },
        notification:  {
            get: function () {
                return this.$store.getters.notification;
            },
            set: function (val) {
                this.$store.commit('SET_NOTIFICATION', val);
            }
        },
        hasNotificationsPending () {
            return this.notificationQueue.length > 0
        }
    },
    watch: {
        notification () {
            if (!this.notification && this.hasNotificationsPending) {
                this.$store.commit('SHIFT_NOTIFICATION_QUEUE');
                this.$nextTick(() => {
                    this.notification = true
                })
            }
        }
    },
    methods: {
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