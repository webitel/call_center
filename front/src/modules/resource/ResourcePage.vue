<template>
    <v-dialog :value="resource" persistent max-width="600px">
        <v-form v-model="valid">
            <v-card>
                <v-card-text>
                    <v-container grid-list-md>
                        <v-layout wrap>
                            <v-flex xs12 sm6>
                                <v-text-field
                                        ref="name"
                                        v-model="model.name"
                                        :rules="[() => !!model.name || $t('base.error.fieldRequired')]"
                                        :label="`${$t('resource.page.name')}*`"
                                        required>
                                </v-text-field>
                            </v-flex>
                            <v-flex xs12 sm6>
                                <v-text-field
                                        ref="limit"
                                        type="number"
                                        v-model="model.limit"
                                        :rules="[() => !!model.limit || $t('base.error.fieldRequired')]"
                                        :label="`${$t('resource.page.limit')}*`"
                                        required>
                                </v-text-field>
                            </v-flex>

                            <v-flex xs12 sm6>
                                <v-text-field
                                        ref="number"
                                        v-model="model.number"
                                        :rules="[() => !!model.number || $t('base.error.fieldRequired')]"
                                        :label="`${$t('resource.page.number')}*`"
                                        required>
                                </v-text-field>
                            </v-flex>
                            <v-flex xs12 sm6>
                                <v-text-field
                                        ref="max_successively_errors"
                                        type="number"
                                        v-model="model.max_successively_errors"
                                        :rules="[() => !!model.max_successively_errors || $t('base.error.fieldRequired')]"
                                        :label="`${$t('resource.page.max_successively_errors')}*`"
                                        >
                                </v-text-field>
                            </v-flex>
                        </v-layout>
                    </v-container>
                </v-card-text>

                <v-card-actions>
                    <v-spacer></v-spacer>
                    <v-btn color="blue darken-1" flat @click="cancel()">{{$t('base.page.close')}}</v-btn>
                    <v-btn color="blue darken-1" :disabled="!valid" flat @click="save()">{{$t('base.page.save')}}</v-btn>
                </v-card-actions>

            </v-card>
        </v-form>
    </v-dialog>
</template>

<script>

    import {CLOSE_PAGE} from './resourceStore'

    export default {
        name: "ResourcePage",
        data: () => {
            return {
                valid: false,
                model: {}
            }
        },
        computed: {
            resource() {
                return this.$store.getters['resource/resource']
            }
        },
        watch: {
            resource(value) {
                if (value) {
                    this.model = value;
                } else {
                    this.model = {}
                }
            }
        },
        methods: {
            save() {

            },
            cancel() {
                this.$store.commit(`resource/${CLOSE_PAGE}`)
            }
        }
    }
</script>

<style scoped>

</style>