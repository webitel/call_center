export const CLEAR_ERROR = "CLEAR_ERROR";

export const calendarStore = {
    namespaced: true,
    state: {
        calendars: [{name: "aaa"}],
        status: {
            loading: false,
            success: true,
            error: false
        }
    },
    getters: {
        list: state => state.calendars,
        loading: state => state.status.loading,
    },
    mutations: {
        [CLEAR_ERROR](state){
            state.status = {
                loading: false,
                success: false,
                error: false
            };
        },
    },
    actions: {
        clearError({ commit }) {
            commit(CLEAR_ERROR);
        }
    }
};