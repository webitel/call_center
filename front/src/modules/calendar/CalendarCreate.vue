<template>
    <v-form v-model="valid">
        <v-layout row justify-center>
        <v-dialog :value="calendar" persistent max-width="600px">
            <v-card>
                <v-card-title>
                    <span class="headline">{{$t('calendar.page.header')}}</span>
                </v-card-title>
                <v-card-text>
                    <v-container grid-list-md>
                        <v-layout wrap>
                            <v-flex xs12>
                                <v-text-field
                                        ref="name"
                                        v-model="name"
                                        :rules="[() => !!name || $t('base.error.fieldRequired')]"
                                        :label="`${$t('calendar.page.name')}*`"
                                        required>
                                </v-text-field>
                            </v-flex>

                            <v-flex xs12>
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
                    <v-btn color="blue darken-1" flat @click="cancel()">{{$t('base.page.close')}}</v-btn>
                    <v-btn color="blue darken-1" :disabled="!valid" flat @click="save()">{{$t('base.page.save')}}</v-btn>
                </v-card-actions>
            </v-card>
        </v-dialog>
    </v-layout>
    </v-form>
</template>

<script>
    export default {
        name: "NewCalendar",
        data: () => {
            return {
                name: null,
                start: null,
                finish: null,
                timezone: null,
                showStart: false,
                showFinish: false,
                valid: false,
                timezones: ["A"],
            }
        },
        props: {
            dialog: Boolean
        },
        computed: {
            calendar() {
                return !!this.$store.getters['calendar/calendar']
            }
        },
        methods: {
            formatDate (date) {
                if (!date) return null;

                const [year, month, day] = date.split('-');
                return `${month}/${day}/${year}`
            },
            parseDate (date) {
                if (!date) return null;

                const [month, day, year] = date.split('/');
                return `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
            },
            cancel() {
                this.$store.dispatch('calendar/cancelNew')
            },
            save() {

            }
        }
    }
</script>

<style scoped>

</style>