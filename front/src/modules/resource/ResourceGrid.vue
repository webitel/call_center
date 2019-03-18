<template>
    <div>
        <v-toolbar color="transparent">
            <v-toolbar-title>{{$t('resource.grid.name')}}</v-toolbar-title>
            <v-spacer></v-spacer>

            <ThrottleSearch :value.sync="filter"></ThrottleSearch>

            <v-btn icon @click="refresh()">
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
                    :items="resources"
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
                        <td class="">{{ props.item.limit }}</td>
                        <td class="">
                            <v-icon v-if="props.item.reserve">
                                radio_button_checked
                            </v-icon>
                            <v-icon v-else="!props.item.reserve">
                                radio_button_unchecked
                            </v-icon>
                        </td>
                        <td class="">{{ props.item.rps }}</td>
                        <td class="text-xs-right">
                            <v-btn icon small >
                                <v-icon color="green" v-if="props.item.enabled">toggle_on</v-icon>
                                <v-icon v-if="!props.item.enabled">toggle_off</v-icon>
                            </v-btn>


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

        <v-dialog v-if="deleteResource" :value="deleteResource" persistent max-width="290">
            <v-card>
                <v-card-title class="headline">{{$t('resource.deleteDialog.header')}}</v-card-title>
                <v-card-text>
                    {{$t('resource.deleteDialog.text', {name: deleteResource.name})}}
                </v-card-text>
                <v-card-actions>
                    <v-spacer></v-spacer>
                    <v-btn color="green darken-1" v-if="deleteResource" autofocus flat @click="deleteResource = null">{{$t('base.dialog.cancel')}}</v-btn>
                    <v-btn color="error darken-1" flat @click="confirmDelete()">{{$t('base.dialog.delete')}}</v-btn>
                </v-card-actions>
            </v-card>
        </v-dialog>
    </div>
</template>

<script>
    import ThrottleSearch from '../../components/ThrottleSearch'

    import {SET_PAGINATION, SET_FILTER, NEW_RECORD} from './resourceStore'
    export default {
        name: "ResourceGrid",
        components: {
            ThrottleSearch
        },
        data() {
            return {
                deleteResource: null,
                headers: [
                    {
                        text: this.$t('resource.page.name'),
                        align: 'left',
                        sortable: true,
                        value: 'name',
                        width: '40%'
                    },
                    {
                        text: this.$t('resource.page.limit'),
                        //align: 'center',
                        sortable: true,
                        value: 'limit',
                        width: '20%'
                    },
                    {
                        text: this.$t('resource.page.reserve'),
                        //align: 'center',
                        sortable: true,
                        value: 'reserve',
                        width: '20%'
                    },
                    {
                        text: this.$t('resource.page.rps'),
                        //align: 'center',
                        sortable: true,
                        value: 'rps',
                        width: '20%'
                    },
                    {
                        text: '',
                        value: '',
                        align: 'right',
                        sortable: false,
                        width: '140px'
                    }

                ]
            }
        },
        watch: {
            pagination: {
                async handler () {
                    await this.$store.dispatch('resource/getData');
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
                    return this.$store.getters[`resource/pagination`]
                },
                set: function (value) {
                    this.$store.commit(`resource/${SET_PAGINATION}`, value);
                }
            },
            filter: {
                get: function() {
                    return this.$store.getters[`resource/filter`]
                },
                set: function(value) {
                    this.$store.commit(`resource/${SET_FILTER}`, value);
                    this.$store.dispatch('resource/getData');
                }
            },
            resources() {
                return this.$store.getters['resource/list'];
            },
            loading() {
                return this.$store.getters['resource/loading'];
            },
            eof() {
                return this.$store.getters['resource/eof'];
            },
            error() {
                return this.$store.getters['resource/error'];
            }
        },
        methods: {
            loadMore() {
                if (this.eof || this.error) {
                    return
                }

                this.pagination.page++;
            },
            refresh() {
                this.$store.dispatch(`resource/reload`);
            },
            editItem(item) {
                this.$router.push({path: `/resource/${item.id}`});
            },
            deleteItem(item) {
                this.deleteResource = item;
            },
            async confirmDelete() {
                await this.$store.dispatch('resource/deleteResource', this.deleteResource.id);
                this.refresh();
                this.deleteResource = null;
            },
            create() {
                this.$store.commit(`resource/${NEW_RECORD}`)
            }
        }
    }
</script>

<style scoped>

</style>