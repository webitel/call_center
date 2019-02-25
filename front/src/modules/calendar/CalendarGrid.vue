<template>
    <div>
        <v-toolbar color="transparent">
            <v-toolbar-title>{{$t('calendar.grid.name')}}</v-toolbar-title>
            <v-spacer></v-spacer>

            <ThrottleSearch :currentValue="pagination.filter" dispatchName="calendar/setFilter"></ThrottleSearch>

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

        <v-data-table
                :headers="headers"
                :items="calendars"
                :hide-actions="true"
                :loading="loading"
                :pagination.sync="pagination"
                :disable-initial-sort="true"
                class="elevation-1"
        >
            <template slot="items" slot-scope="props">
                <tr class="">
                    <td>
                        <v-btn flat small  @click="editItem(props.item)">{{ props.item.name }}</v-btn>
                    </td>
                    <td class="">{{ props.item.timezone }}</td>
                    <td class="">{{ props.item.start }}</td>
                    <td class="">{{ props.item.finish }}</td>
                    <td class="text-xs-right justify-center px-0">
                        <v-icon
                                small
                                class="mr-2"
                                @click="editItem(props.item)"
                        >
                            edit
                        </v-icon>
                        <v-icon
                                small
                                class="mr-2"
                                @click="deleteItem(props.item)"
                        >
                            delete
                        </v-icon>
                    </td>
                </tr>
            </template>
        </v-data-table>

        <CalendarCreateDialog ></CalendarCreateDialog>
    </div>
</template>

<script>
    import CalendarCreateDialog from './CalendarCreate'
    import {SET_PAGINATION} from './calendatStore'
    //TODO add app
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
                        value: 'name'
                    },
                    {
                        text: this.$t('calendar.page.timezone'),
                        //align: 'center',
                        sortable: true,
                        value: 'timezone'
                    },
                    {
                        text: this.$t('calendar.page.start'),
                        //align: 'center',
                        sortable: true,
                        value: 'start'
                    },
                    {
                        text: this.$t('calendar.page.finish'),
                        //align: 'center',
                        sortable: true,
                        value: 'finish'
                    },
                    {
                        text: '',
                        value: 'name',
                        align: 'right',
                        sortable: false
                    }

                ]
            }
        },
        watch: {
            pagination: {
                handler () {
                    this.$store.dispatch('calendar/getData');
                },
                deep: true
            }
        },
        computed: {
            pagination: {
                get: function () {
                    return this.$store.getters[`calendar/pagination`]
                },
                set: function (value) {
                    this.$store.commit(`calendar/${SET_PAGINATION}`, value)
                }
            },
            calendars() {
                return this.$store.getters['calendar/list'];
            },
            loading() {
                return this.$store.getters['calendar/loading'];
            },
            error() {
                return 'TEST' // this.$store.getters['calendar/error'];
            }
        },
        methods: {
            resetPagination() {
                this.$store.dispatch('calendar/resetPagination')
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