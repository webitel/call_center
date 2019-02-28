import Vue from 'vue'
import Vuex from 'vuex'

//TODO
import {calendarStore} from '../modules/calendar/calendatStore'
import {Application} from '../core/app'

Vue.use(Vuex);

export const ADD_NOTIFICATION = "ADD_NOTIFICATION";
export const SHIFT_NOTIFICATION_QUEUE = "SHIFT_NOTIFICATION_QUEUE";
export const SET_NOTIFICATION = "SET_NOTIFICATION";

export default new Vuex.Store({
    debug: true,
    modules: {
        calendar: calendarStore
    },
    state: {
        notificationQueue: [],
        notification: false,
        toast: {
            text: '',
            color: 'success',
            timeout: 5000
        },
        core: new Application()
    },
    mutations: {
        [ADD_NOTIFICATION](state, toast) {
            if (typeof toast !== 'object') return;
            state.notificationQueue.push(toast);

            if (!state.notification) {
                state.toast = state.notificationQueue.shift();
                state.notification = true
            }
        },
        [SHIFT_NOTIFICATION_QUEUE](state) {
            state.toast = state.notificationQueue.shift();
        },
        [SET_NOTIFICATION](state, payload) {
            state.notification = payload;
        }
    },
    getters: {
        core: state => state.core,
        notification: state => state.notification,
        notificationQueue: state => state.notificationQueue,
        toast: state => state.toast,

        timezonesIds: state => state.core.getTimezones().map(i => i.id)
    },
    actions: {
        listTimezones() {

        }
    }
})
