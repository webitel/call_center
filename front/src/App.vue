<template>
  <v-app id="inspire" dark>
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
                  dark
                  v-else-if="item.divider"
                  class="my-3"
                  :key="i"
          ></v-divider>
          <v-list-tile
                  :key="i"
                  v-else
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
    <v-toolbar fixed app  clipped-left>
      <v-toolbar-side-icon @click.native="drawer = !drawer"></v-toolbar-side-icon>
      <span class="title ml-3 mr-5">Call&nbsp;<span class="text">center</span></span>
      <v-spacer></v-spacer>
    </v-toolbar>
    <v-content>
      <v-container fluid fill-height class="lighten-4">
        <v-layout >
          <v-flex >
            <router-view/>
          </v-flex>
        </v-layout>
      </v-container>
    </v-content>
  </v-app>
</template>


<script>
    export default {
        name: 'App',
        components: {

        },
        created () {
            this.links = this.$router.options.routes.
            filter(({main}) => main === true).
            map(({name, icon, path}) => ({
                name,
                icon,
                path
            }));
        },
        data: () => {
            return {
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

<style>
    #keep main .container {
        height: 660px;
    }
    .navigation-drawer__border {
        display: none;
    }
    .text {
        font-weight: 400;
    }
</style>
