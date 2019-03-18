export const CLEAR_ERROR = "CLEAR_ERROR";
export const LOADING = "LOADING";
export const SUCCESS = "SUCCESS";
export const ERROR = "ERROR";
export const NEW_RECORD = "NEW_RECORD";
export const CLOSE_PAGE = "CLOSE_PAGE";

export const SET_PAGINATION = "SET_PAGINATION";
export const SET_ITEMS = "SET_ITEMS";
export const SET_ITEM = "SET_ITEM";
export const SET_FILTER = "SET_FILTER";
export const RELOAD = "RELOAD";

const ROW_PER_PAGE = 20;

const DEFAULT_PAGINATION = {
    page: 1,
    descending: false,
    rowsPerPage: -1,
    sortBy: "name"
};

export const resourceStore = {
    namespaced: true,
    state: {
        resources: [],
        filter: "",
        pagination: DEFAULT_PAGINATION,
        eof: false,
        resource: null,
        status: {
            loading: false,
            success: true,
            error: false
        }
    },
    getters: {
        list: state => state.resources,
        resource: state => state.resource,

        pagination: state => state.pagination,
        filter: state => state.filter,
        eof: state => state.eof,
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
        [SET_PAGINATION](state, payload) {
            state.resources.length = 0;
            state.pagination = payload;

        },
        [SET_ITEMS](state, items) {
            state.eof = items.length < ROW_PER_PAGE;
            state.resources = state.resources.concat(items);
        },
        [SET_FILTER](state, filter) {
            state.filter = filter || "";
            state.pagination.page = 1;
            state.resources.length = 0;
        },
        [RELOAD](state) {
            state.resources= [];
            state.pagination.page = 1;
        },
        [NEW_RECORD](state) {
            state.resource = {
                id: 0
            }
        },
        [SET_ITEM](state, resource) {
            state.resource = resource;
        },
        [CLOSE_PAGE](state) {
            state.resource = null
        },
    },
    actions: {
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

            return rootGetters.core.request('get', `/resources?&per_page=${ROW_PER_PAGE}&${params.join('&')}`)
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

        deleteResource({state, commit, rootGetters}, id) {
            commit(LOADING);
            return rootGetters.core.request('delete', `/resources/${id}`)
                .then(response => {
                    commit(SUCCESS);
                })
                .catch(err => {
                    commit(ERROR, err);
                })
        },

        getItem({state, commit, rootGetters}, id) {
            commit(LOADING);
            return rootGetters.core.request('get', `/resources/${id}`)
                .then(response => {
                    if (response.data) {
                        commit(SET_ITEM, response.data)
                    }
                    commit(SUCCESS);
                })
                .catch(err => {
                    commit(ERROR, err);
                })

        },

        reload({dispatch, commit}) {
            commit("RELOAD");
            return dispatch("getData")
        },
    }
};