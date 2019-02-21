export const CLEAR_ERROR = "CLEAR_ERROR";
export const LOADING = "LOADING";
export const SUCCESS = "SUCCESS";
export const ERROR = "ERROR";
export const NEW_RECORD = "NEW_RECORD";
export const CANCEL_NEW_RECORD = "CANCEL_NEW_RECORD";
export const SET_PAGINATION = "SET_PAGINATION";
export const SET_ITEMS = "SET_ITEMS";

const ROW_PER_PAGE = 20;

const DEFAULT_PAGINATION = {
    page: 1,
    descending: false,
    rowsPerPage: ROW_PER_PAGE,
    sortBy: "name",
    filter: ""
};

import axios from 'axios'

export const calendarStore = {
    namespaced: true,
    state: {
        calendars: [],
        pagination: DEFAULT_PAGINATION,
        eof: false,
        calendar: null,
        status: {
            loading: false,
            success: true,
            error: false
        }
    },
    getters: {
        pagination: state => state.pagination,
        eof: state => state.eof,
        calendar: state => state.calendar,
        list: state => state.calendars,
        loading: state => state.status.loading,
        error: state => state.status.error,
    },
    mutations: {
        [LOADING](state) {
            state.status = {
                loading: true,
                success: false,
                error: false
            };
        },
        [SUCCESS](state){
            state.status = {
                loading: false,
                success: true,
                error: false
            };
        },
        [ERROR](state,payload){
            state.status = {
                loading: false,
                success: false,
                error: payload
            };
            state.end = true;
        },
        [CLEAR_ERROR](state){
            state.status = {
                loading: false,
                success: false,
                error: false
            };
        },
        [NEW_RECORD](state) {
            state.calendar = {
                id: 0
            }
        },
        [CANCEL_NEW_RECORD](state) {
            state.calendar = null
        },
        [SET_PAGINATION](state, payload) {
            state.pagination = payload
        },
        [SET_ITEMS](state, items) {
            state.eof = items.length < ROW_PER_PAGE;
            state.calendars = [].concat(items);
        }
    },
    actions: {
        new({commit}) {
            commit(NEW_RECORD)
        },
        cancelNew({commit}) {
            commit(CANCEL_NEW_RECORD)
        },
        clearError({ commit }) {
            commit(CLEAR_ERROR);
        },
        setFilter({state, commit}, value) {
            state.pagination.filter = value || "";
            commit(SET_PAGINATION, state.pagination)
        },
        getData({state, commit}) {
            commit(LOADING);
            const {descending, sortBy, page, filter} = state.pagination;
            const params = [];
            if (descending) {
                params.push('desc=1');
            }
            if (sortBy) {
                params.push(`sort=${encodeURIComponent(sortBy)}`)
            }
            if (filter) {
                try {
                    params.push(`filter=${encodeURIComponent(filter)}`)
                } catch (e) {
                    commit(ERROR, e);
                    return;
                }
            }

            return axios.get(`http://10.10.10.25:10023/api/v2/calendars?&per_page=40&${params.join('&')}`)
                .then(response => {
                    if (response.data instanceof Array) {
                        commit(SET_ITEMS, response.data)
                    }
                    commit(SUCCESS);
                })
                .catch(err => {
                    commit(ERROR, err);
                });
        },
        resetPagination({dispatch, commit}) {
            commit(SET_PAGINATION, DEFAULT_PAGINATION);
            return dispatch('getData');
        }
    }
};