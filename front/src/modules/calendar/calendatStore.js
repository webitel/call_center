export const CLEAR_ERROR = "CLEAR_ERROR";
export const LOADING = "LOADING";
export const SUCCESS = "SUCCESS";
export const ERROR = "ERROR";
export const NEW_RECORD = "NEW_RECORD";
export const CANCEL_NEW_RECORD = "CANCEL_NEW_RECORD";
export const SET_PAGINATION = "SET_PAGINATION";
export const SET_ITEMS = "SET_ITEMS";
export const SET_FILTER = "SET_FILTER";
export const RELOAD = "RELOAD";

const ROW_PER_PAGE = 20;

const DEFAULT_PAGINATION = {
    page: 1,
    descending: false,
    rowsPerPage: -1,
    sortBy: "name"
};

export const calendarStore = {
    namespaced: true,
    state: {
        calendars: [],
        filter: "",
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
        filter: state => state.filter,
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
        [SUCCESS](state) {
            state.status = {
                loading: false,
                success: true,
                error: false
            };
        },
        [ERROR](state,payload) {
            state.status = {
                loading: false,
                success: false,
                error: payload
            };
            state.end = true;
        },
        [CLEAR_ERROR](state) {
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
            state.calendars.length = 0;
            state.pagination = payload;

        },
        [SET_ITEMS](state, items) {
            state.eof = items.length < ROW_PER_PAGE;
            state.calendars = state.calendars.concat(items);
        },
        [SET_FILTER](state, filter) {
            state.filter = filter || "";
            state.pagination.page = 1;
            state.calendars.length = 0;
        },
        [RELOAD](state) {
            state.calendars= [];
            state.pagination.page = 1;
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

        getData({state, commit, rootGetters}) {
            commit(LOADING);
            const {descending, sortBy, page} = state.pagination;

            const filter = state.filter;
            const params = [`page=${page - 1}`];
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

            return rootGetters.core.request('get', `/calendars?&per_page=${ROW_PER_PAGE}&${params.join('&')}`)
                .then(response => {
                    if (response.data && response.data.items instanceof Array) {
                        commit(SET_ITEMS, response.data.items)
                    }
                    commit(SUCCESS);
                })
                .catch(err => {
                    commit(ERROR, err);
                });
        },

        reload({dispatch, commit}) {
            commit("RELOAD");
            return dispatch("getData")
        },
        createCalendar({state, commit, rootGetters}, calendar = {}) {
            commit(LOADING);
            return rootGetters.core.request('post', `/calendars`, calendar)
                .then(response => {
                    if (response.data instanceof Array) {
                        commit(SET_ITEMS, response.data)
                    }
                    commit(SUCCESS);
                })
                .catch(err => {
                    commit(ERROR, err);
                });
        }
    }
};