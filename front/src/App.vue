<template>
    <v-app id="inspire" :dark="dark">
        <v-navigation-drawer
                fixed
                clipped
                app
                v-model="drawer"
        >
            <v-list
                    dense
                    class=" lighten-4"
            >
                <template v-for="(item, i) in links">
                    <v-layout
                            row
                            v-if="item.heading"
                            align-center
                            :key="i"
                    >
                        <v-flex xs6>
                            <v-subheader v-if="item.heading">
                                {{ item.heading }}
                            </v-subheader>
                        </v-flex>
                        <v-flex xs6 class="text-xs-right">
                            <v-btn small flat>edit</v-btn>
                        </v-flex>
                    </v-layout>
                    <v-divider
                            v-else-if="item.divider"
                            class="my-3"
                            :key="i"
                    ></v-divider>
                    <v-list-tile
                            v-else
                            :key="i"
                            @click="()=>{goTo(item)}"
                    >
                        <v-list-tile-action>
                            <v-icon>{{ item.icon }}</v-icon>
                        </v-list-tile-action>
                        <v-list-tile-content>
                            <v-list-tile-title>
                                {{ $t(`link.${item.name}`) }}
                            </v-list-tile-title>
                        </v-list-tile-content>
                    </v-list-tile>
                </template>
            </v-list>
        </v-navigation-drawer>
        <v-toolbar fixed app clipped-left>
            <v-toolbar-side-icon @click.native="drawer = !drawer"></v-toolbar-side-icon>
            <span class="title ml-3 mr-5">Call&nbsp;<span class="text">center</span></span>
            <v-spacer></v-spacer>

            <v-menu bottom left>
                <v-btn
                        color="transparent"
                        small
                        icon
                        slot="activator"
                >
                    <v-icon>account_circle</v-icon>
                </v-btn>
                <v-list>
                    <v-list-tile
                            @click="dark = !dark"
                    >
                        <v-list-tile-title>Dark mode</v-list-tile-title>
                    </v-list-tile>
                </v-list>
            </v-menu>

        </v-toolbar>

        <v-snackbar
                v-model="notification"
                :bottom="false"
                :left="false"
                :color="toast.color"
                :multi-line="false"
                :right="true"
                :timeout="toast.timeout"
                :top="true"
                :vertical="false"
                :auto-height="true"
        >
            <v-avatar>
                <v-icon large>error</v-icon>
            </v-avatar>

            <div class="toast_note">
                <span>{{toast.text}}</span>
            </div>
            <v-btn flat icon @click.native="notification = false">
                <v-icon>close</v-icon>
            </v-btn>
        </v-snackbar>

        <v-layout>
            <v-content class="content-scroll">
                <v-container fluid fill-height class="lighten-4">
                    <v-layout>
                        <v-flex>
                            <transition name="fade">
                                <router-view/>
                                <!--<keep-alive>-->
                                <!--<router-view/>-->
                                <!--</keep-alive>-->
                            </transition>
                        </v-flex>
                    </v-layout>
                </v-container>
            </v-content>
        </v-layout>
    </v-app>
</template>


<script>
    import toast from './mixins/toast'

    export default {
        name: 'App',
        mixins: [toast],
        components: {},
        created() {
            this.links = this.$router.options.routes.filter(({main}) => main === true).map(({name, icon, path}) => ({
                name,
                icon,
                path
            }));
        },
        mounted() {

        },
        data: () => {
            return {
                dark: true,
                drawer: null,
                links: []
            }
        },
        methods: {
            goTo({path}) {
                this.$router.push({path})
            }
        },
        props: {
            core: Object
        }
    }
</script>

<style scoped>
    #inspire {
        /*overflow-y: hidden;*/
    }

    .content-scroll {
        /*overflow-y: scroll;*/
    }

    .toast_note {
        white-space: pre-wrap;
        word-wrap: break-word;
    }

</style>

<style>
    html {
        /*overflow-y: hidden;*/
    }

    .fade-enter-active, .fade-leave-active {
        transition-property: opacity;
        transition-duration: .2s;
    }

    .fade-enter-active {
        transition-delay: .2s;
    }

    .fade-enter, .fade-leave-active {
        opacity: 0
    }

    .table__fixed table {
        table-layout: fixed;
    }

    .table__fixed table .table_data_view__on_hover {
        display: none;
    }

    .table__fixed table tr:hover .table_data_view__on_hover {
        display: block;
    }

    ::-webkit-scrollbar {
        width: 8px;
    }

    ::-webkit-scrollbar-thumb:vertical {
        margin: 50px;
        background-color: #999;
        -webkit-border-radius: 5px;
    }

    ::-webkit-scrollbar-button:start:decrement,
    ::-webkit-scrollbar-button:end:increment {
        height: 5px;
        display: block;
    }

    /*
    table  tbody tr:hover  .datatable-auto-show-row > * {
        display: flex;
    }
    table  tbody tr  .datatable-auto-show-row > * {
        display: none;
    }
    */
</style>
