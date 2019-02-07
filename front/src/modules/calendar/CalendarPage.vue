<template>
    <v-form v-model="valid">
        <v-card>
            <v-card-text>
                <v-container grid-list-md>
                    <v-layout wrap>
                        <v-flex xs12 sm6>
                            <v-text-field
                                    ref="name"
                                    v-model="name"
                                    :rules="[() => !!name || $t('base.error.fieldRequired')]"
                                    :label="`${$t('calendar.page.name')}*`"
                                    required>
                            </v-text-field>
                        </v-flex>

                        <v-flex xs12 sm6>
                            <v-autocomplete
                                    ref="timezone"
                                    v-model="timezone"
                                    :rules="[() => !!timezone || $t('base.error.fieldRequired')]"
                                    :items="timezones"
                                    :label="`${$t('calendar.page.timezone')}*`"
                                    required
                            ></v-autocomplete>
                        </v-flex>

                        <v-flex xs12 sm6>
                            <v-menu
                                    ref="showStart"
                                    v-model="showStart"
                                    :close-on-content-click="false"
                                    :nudge-right="40"
                                    lazy
                                    transition="scale-transition"
                                    offset-y
                                    full-width
                                    max-width="290px"
                                    min-width="290px"
                            >
                                <v-text-field
                                        slot="activator"
                                        v-model="start"
                                        :label="`${$t('calendar.page.start')}`"
                                        persistent-hint
                                        prepend-icon="event"
                                ></v-text-field>
                                <v-date-picker v-model="start" no-title @input="showStart = false"></v-date-picker>
                            </v-menu>
                        </v-flex>

                        <v-flex xs12 sm6>
                            <v-menu
                                    ref="showFinish"
                                    v-model="showFinish"
                                    :close-on-content-click="false"
                                    :nudge-right="40"
                                    lazy
                                    transition="scale-transition"
                                    offset-y
                                    full-width
                                    max-width="290px"
                                    min-width="290px"
                            >
                                <v-text-field
                                        slot="activator"
                                        v-model="finish"
                                        :label="`${$t('calendar.page.finish')}`"
                                        persistent-hint
                                        prepend-icon="event"
                                ></v-text-field>
                                <v-date-picker v-model="finish" no-title @input="showFinish = false"></v-date-picker>
                            </v-menu>
                        </v-flex>


                    </v-layout>
                </v-container>
                <small>*{{$t('base.page.indicatesRequiredField')}}</small>
            </v-card-text>
            <v-card-actions>
                <v-spacer></v-spacer>
                <v-btn color="blue darken-1" flat @click="close()">{{$t('base.page.close')}}</v-btn>
                <v-btn color="blue darken-1" :disabled="!valid" flat @click="save()">{{$t('base.page.save')}}</v-btn>
            </v-card-actions>
        </v-card>
    </v-form>
</template>

<script>
    export default {
        name: "CalendarPage"
    }
</script>

<style scoped>

</style>