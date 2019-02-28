import Vue from 'vue'
import Vuetify from 'vuetify/lib'
import 'vuetify/src/stylus/app.styl'

Vue.use(Vuetify, {
    iconfont: 'md',
    theme: {
        primary: '#82B1FF',
        // primary: '#142dbf',
        secondary: '#424242',
        accent: '#387E75',
        error: '#FF5252',
        info: '#2196F3',
        success: '#4CAF50',
        warning: '#FFC107'
    }
});
