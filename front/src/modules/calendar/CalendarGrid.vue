<template>
    <div>
        <v-toolbar color="transparent" >
            <v-toolbar-title>{{$t('calendar.grid.name')}}</v-toolbar-title>
            <v-spacer></v-spacer>

            <ThrottleSearch :value.sync="filter"></ThrottleSearch>

            <v-btn icon @click="resetPagination()">
                <v-icon>refresh</v-icon>
            </v-btn>
            <v-btn @click="create()">
                new
                <v-icon>add</v-icon>
            </v-btn>

            <v-menu bottom left>
                <v-btn
                        slot="activator"
                        icon
                >
                    <v-icon>more_vert</v-icon>
                </v-btn>

                <v-list>
                    <v-list-tile>
                        <v-list-tile-title>One</v-list-tile-title>
                    </v-list-tile>
                </v-list>
            </v-menu>
        </v-toolbar>

        <v-flex pt-2>
            <v-data-table
                    :headers="headers"
                    :items="calendars"
                    :hide-actions="true"
                    :loading="loading"
                    class="elevation-1 table__fixed"
                    :disable-initial-sort="true"
                    :pagination.sync="pagination"
                    v-infinite-scroll="loadMore"
                    infinite-scroll-disabled="loading"
            >
                <template slot="items" slot-scope="props">
                    <tr class="">
                        <td>
                            <v-btn flat small  @click="editItem(props.item)">{{ props.item.name }}</v-btn>
                        </td>
                        <td class="">{{ props.item.timezone }}</td>
                        <td class="">{{ props.item.start }}</td>
                        <td class="">{{ props.item.finish }}</td>
                        <td class="text-xs-right">
                            <v-menu bottom left>
                                <v-btn
                                        color="transparent"
                                        small
                                        icon
                                        slot="activator"
                                >
                                    <v-icon>more_vert</v-icon>
                                </v-btn>
                                <v-list>
                                    <v-list-tile
                                            @click="editItem(props.item)"
                                    >
                                        <v-list-tile-title>Edit</v-list-tile-title>
                                    </v-list-tile>
                                    <v-list-tile
                                            @click="deleteItem(props.item)"
                                    >
                                        <v-list-tile-title>Delete</v-list-tile-title>
                                    </v-list-tile>
                                </v-list>
                            </v-menu>
                        </td>
                    </tr>
                </template>
            </v-data-table>
        </v-flex>

        <CalendarCreateDialog ></CalendarCreateDialog>
    </div>
</template>

<script>
    import CalendarCreateDialog from './CalendarCreate'
    import {SET_PAGINATION, SET_FILTER} from './calendatStore'

    import ThrottleSearch from '../../components/ThrottleSearch'

    export default {
        components: {
            CalendarCreateDialog,
            ThrottleSearch
        },
        name: "Calendar",
        data() {
            return {
                headers: [
                    {
                        text: this.$t('calendar.page.name'),
                        align: 'left',
                        sortable: true,
                        value: 'name',
                        width: '40%'
                    },
                    {
                        text: this.$t('calendar.page.timezone'),
                        //align: 'center',
                        sortable: true,
                        value: 'timezone',
                        width: '20%'
                    },
                    {
                        text: this.$t('calendar.page.start'),
                        //align: 'center',
                        sortable: true,
                        value: 'start',
                        width: '20%'
                    },
                    {
                        text: this.$t('calendar.page.finish'),
                        //align: 'center',
                        sortable: true,
                        value: 'finish',
                        width: '20%'
                    },
                    {
                        text: '',
                        value: '',
                        align: 'right',
                        sortable: false,
                        width: '120px'
                    }

                ]
            }
        },
        watch: {
            pagination: {
                async handler () {
                    await this.$store.dispatch('calendar/getData');
                },
                deep: true
            },
            error(err) {
                if (err) {
                    this.$store.commit('ADD_NOTIFICATION', {text: err.message, color: 'red', timeout: 5000});
                }
            }
        },
        computed: {
            pagination: {
                get: function () {
                    return this.$store.getters[`calendar/pagination`]
                },
                set: function (value) {
                    this.$store.commit(`calendar/${SET_PAGINATION}`, value);
                }
            },
            filter: {
                get: function() {
                    return this.$store.getters[`calendar/filter`]
                },
                set: function(value) {
                    this.$store.commit(`calendar/${SET_FILTER}`, value);
                    this.$store.dispatch('calendar/getData');
                }
            },
            calendars() {
                return this.$store.getters['calendar/list'];
            },
            loading() {
                return this.$store.getters['calendar/loading'];
            },
            eof() {
                return this.$store.getters['calendar/eof'];
            },
            error() {
                return this.$store.getters['calendar/error'];
            }
        },
        methods: {
            loadMore() {
                if (this.eof || this.error) {
                    return
                }

                this.pagination.page++;
            },
            resetPagination() {
                this.$store.dispatch(`calendar/reload`);
            },
            editItem(item) {
                this.$router.push({path: `/calendar/${item.id}`})
            },
            deleteItem(item) {

            },
            create() {
                this.$store.dispatch('calendar/new')
            }
        }
    }
</script>

<style scoped>

</style>