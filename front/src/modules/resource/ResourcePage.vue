<template>

    <div>
        <v-toolbar color="transparent">
            <v-btn color="" @click="cancel()">{{$t('base.page.close')}}</v-btn>
            <v-btn color="success" :disabled="!valid" @click="save()">{{$t('base.page.save')}}</v-btn>
        </v-toolbar>

        <v-layout pt-2>
            <v-form >
                <v-card>
                    <v-card-text>
                        <v-layout wrap >
                            <v-flex xs12 sm8 md8 >
                                <v-container grid-list-md>
                                    <v-layout wrap >
                                        <v-flex xs12 sm6 >
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
                                                    ref="rps"
                                                    type="number"
                                                    v-model="model.rps"
                                                    :rules="[() => !!model.rps || $t('base.error.fieldRequired')]"
                                                    :label="`${$t('resource.page.rps')}*`"
                                            >
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
                                                    ref="dialString"
                                                    v-model="model.dialString"
                                                    :rules="[() => !!model.dialString || $t('base.error.fieldRequired')]"
                                                    :label="`${$t('resource.page.dialString')}*`"
                                            >
                                            </v-text-field>
                                        </v-flex>

                                        <v-flex xs12 sm6>
                                            <v-layout row>

                                                <v-switch
                                                        label="Enabled"
                                                ></v-switch>
                                                <v-switch
                                                        label="Reserved"
                                                ></v-switch>
                                            </v-layout>
                                        </v-flex>
                                    </v-layout>
                                </v-container>
                            </v-flex>

                            <v-flex xs12 sm4 md4>
                                Variables
                                <table class="v-table fixed_header">
                                    <thead>
                                    <tr>
                                        <th class="text-sm-left">Name</th>
                                        <th class="text-sm-left">Value</th>
                                        <th class="text-sm-center">
                                            <v-btn icon @click="newVariable = true">
                                                <v-icon>add</v-icon>
                                            </v-btn>
                                        </th>
                                    </tr>
                                    </thead>
                                    <tbody>
                                    <tr v-for="(value, key) in model.variables">
                                        <td>{{key}}</td>
                                        <td class="text-truncate" >{{value}}</td>
                                        <td class="text-sm-center">
                                            <v-btn icon @click="removeVariable(key, value)">
                                                <v-icon>remove</v-icon>
                                            </v-btn>
                                        </td>
                                    </tr>
                                    </tbody>
                                </table>

                            </v-flex>
                        </v-layout>
                    </v-card-text>
                </v-card>


                <v-dialog
                        v-model="newVariable"
                        width="500"
                >
                    <v-card>
                        <v-card-title
                                class="headline lighten-2"
                        >
                            {{$t('resource.page.variableWindowHeader')}}
                        </v-card-title>

                        <v-card-text>
                            <v-text-field
                                    v-model="newVariableName"
                                    :label="`${$t('resource.page.variableName')}`"
                            >
                            </v-text-field>
                            <v-text-field
                                    v-model="newVariableValue"
                                    :label="`${$t('resource.page.variableValue')}`"
                            >
                            </v-text-field>
                        </v-card-text>

                        <v-divider></v-divider>

                        <v-card-actions>
                            <v-spacer></v-spacer>
                            <v-btn
                                    color="primary"
                                    flat
                                    @click="newVariable = false"
                            >
                                Cancel
                            </v-btn>
                            <v-btn
                                    color="success"
                                    flat
                                    @click="newVariable = false"
                            >
                                Add
                            </v-btn>
                        </v-card-actions>
                    </v-card>
                </v-dialog>

            </v-form>
        </v-layout>
    </div>

</template>

<script>
    import {CLOSE_PAGE} from './resourceStore'

    export default {
        name: "ResourcePage",
        data: () => {
            return {
                valid: false,
                newVariable: false,
                newVariableName: "",
                newVariableValue: "",
                model: {
                    variables: {
                    }
                }
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
            removeVariable(key) {
                this.$delete(this.model.variables, key);
            },
            cancel() {
                this.$store.commit(`resource/${CLOSE_PAGE}`)
            }
        }
    }
</script>

<style scoped>
    .fixed_header{
        table-layout: fixed;
        border-collapse: collapse;
    }

</style>