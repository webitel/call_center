import Vue from 'vue'
import './plugins/vuetify'
import App from './App.vue'
import 'roboto-fontface/css/roboto/roboto-fontface.css'
import 'material-design-icons-iconfont/dist/material-design-icons.css'
import router from './router'
import store from './store'
import i18n from './plugins/i18n'
import  './plugins/amcharts'
import  './plugins/infiniteScroll'

import NProgress from 'nprogress'
import 'nprogress/nprogress.css'

Vue.config.productionTip = false;

NProgress.configure({ showSpinner: false });
router.beforeEach((to, from, next) => {
    NProgress.start();
    NProgress.set(0.1);
    next()
});
router.afterEach(() => {
    setTimeout(() => NProgress.done(), 500)
});

new Vue({
    i18n,
    router,
    store,
    render: h => h(App, {
        props: {

        }
    })
}).$mount('#app');
