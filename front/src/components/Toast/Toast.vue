<template>
    <v-snackbar v-model="open" v-bind="options">
        <div class="ctn">
            <div class="title mb-2" v-if="title">{{title}}</div>
            <div class="txt">{{text}}</div>
        </div>
        <v-btn v-if="options.closeable" flat icon @click.native="open = false">
            <!-- <fai :icon="['fal', 'times']" size="lg"></fai> -->
        </v-btn>
    </v-snackbar>
</template>

<script>
    /* TODO */

    export default {
        name: 'toast',
        props: {
            title: String,
            text: String,
            type: String,
            options: Object,
        },
        data() {
            return {
                open: false,
            }
        },
        watch: {
            open: function(val) {
                if (!val) {
                    this.close()
                }
            },
        },
        beforeMount() {
            document.querySelector('#app').appendChild(this.$el)
        },
        mounted() {
            this.open = true
        },
        methods: {
            close() {
                if (this.open) this.open = false
                setTimeout(() => {
                    this.$options.onClose()
                    this.$destroy()
                    removeElement(this.$el)
                }, 700) // wait for close animation
            },
        },
    }

    function removeElement(el) {
        if (typeof el.remove !== 'undefined') {
            el.remove()
        } else {
            el.parentNode.removeChild(el)
        }
    }
</script>