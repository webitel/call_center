import Vue from 'vue'
import './plugins/vuetify'
import App from './App.vue'
import 'roboto-fontface/css/roboto/roboto-fontface.css'
import 'material-design-icons-iconfont/dist/material-design-icons.css'
import router from './router'
import store from './store'
import { Application } from './core/app'
import i18n from './plugins/i18n'
import  './plugins/amcharts'
import  './plugins/infiniteScroll'

Vue.config.productionTip = false;

new Vue({
    i18n,
    router,
    store,
    render: h => h(App, {
        props: {
            core: new Application()
        }
    })
}).$mount('#app');
