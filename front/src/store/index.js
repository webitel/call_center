import Vue from 'vue'
import Vuex from 'vuex'

//TODO
import {calendarStore} from '../modules/calendar/calendatStore'

Vue.use(Vuex);

export default new Vuex.Store({
    debug: true,
    modules: {
        calendar: calendarStore
    },
    state: {

    },
    mutations: {

    },
    actions: {
        listTimezones() {

        }
    }
})
