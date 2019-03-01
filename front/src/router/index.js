import Vue from 'vue'
import Router from 'vue-router'
import NotFound from '@/views/NotFound.vue'

Vue.use(Router);

export default new Router({
    mode: 'history',
    base: process.env.BASE_URL,
    routes: [
        {
            path: '/',
            icon: 'home',
            main: true,
            name: 'home',
            component: () => import('@/views/Home.vue')
        },
        {
            path: '/resource',
            icon: 'sim_card',
            main: true,
            name: 'resource',
            component: () => import('@/modules/resource/ResourceGrid.vue')
        },
        {
            path: '/calendar',
            icon: 'calendar_today',
            main: true,
            name: 'calendar',
            component: () => import('@/modules/calendar/CalendarGrid.vue')
        },
        {
            path: '/calendar/:id',
            main: false,
            name: 'calendarPage',
            component: () => import('@/modules/calendar/CalendarPage.vue')
        },
        {
            path: '*',
            name: 'NotFound',
            component: NotFound
        }
    ]
})
