import Vue from 'vue'
import Router from 'vue-router'
import Home from '@/views/Home.vue'
import NotFound from '@/views/NotFound.vue'

import CalendarGrid from '@/modules/calendar/CalendarGrid.vue'
import CalendarPage from '@/modules/calendar/CalendarPage.vue'

Vue.use(Router)

export default new Router({
    mode: 'history',
    base: process.env.BASE_URL,
    routes: [
        {
            path: '/',
            icon: 'home',
            main: true,
            name: 'home',
            component: Home
        },
        {
            path: '/calendar',
            icon: 'calendar_today',
            main: true,
            name: 'calendar',
            component: CalendarGrid
        },
        {
            path: '/calendar/:id',
            main: false,
            name: 'calendarPage',
            component: CalendarPage
        },
        {
            path: '*',
            name: 'NotFound',
            component: NotFound
        }
    ]
})
