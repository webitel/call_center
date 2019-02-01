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
        <template v-for="(item, i) in items">
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
                  @click="()=>{}"
          >
            <v-list-tile-action>
              <v-icon>{{ item.icon }}</v-icon>
            </v-list-tile-action>
            <v-list-tile-content>
              <v-list-tile-title>
                {{ item.text }}
              </v-list-tile-title>
            </v-list-tile-content>
          </v-list-tile>
        </template>
      </v-list>
    </v-navigation-drawer>
    <v-toolbar app absolute clipped-left>
      <v-toolbar-side-icon @click.native="drawer = !drawer"></v-toolbar-side-icon>
      <span class="title ml-3 mr-5">Call&nbsp;<span class="text">center</span></span>
      <v-spacer></v-spacer>
    </v-toolbar>
    <v-content>
      <v-container fluid fill-height class="lighten-4">
        <v-layout justify-center align-center>
          <v-flex shrink>
            CONTENT
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
  data: () => ({
      drawer: null,
      items: [
          { icon: 'people', text: 'Agents' },
          { icon: 'queue', text: 'Queues' },
          { icon: 'assessment', text: 'Statistics' },
          { icon: 'phonelink', text: 'App downloads' },
          { icon: 'keyboard', text: 'Keyboard shortcuts' },
          { icon: 'settings', text: 'Settings' },
      ]
  }),
  props: {
      source: String
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
