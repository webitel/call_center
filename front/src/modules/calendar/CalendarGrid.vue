<template>
    <div>
        <v-data-table
                :headers="headers"
                :items="calendars"
                :hide-actions="true"
                :loading="loading"
                class="elevation-1"
        >
            <template slot="items" slot-scope="props">
                <td>{{ props.item.name }}</td>
                <td class="text-xs-right">{{ props.item.timezone }}</td>
                <td class="text-xs-right">{{ props.item.start }}</td>
                <td class="text-xs-right">{{ props.item.finish }}</td>
                <td class="text-xs-right">
                    <v-icon
                            small
                            class="mr-2"
                            @click="editItem(props.item)"
                    >
                        edit
                    </v-icon>
                    <v-icon
                            small
                            @click="deleteItem(props.item)"
                    >
                        delete
                    </v-icon>
                </td>
            </template>
        </v-data-table>

        <CalendarCreateDialog :showDialog="showNewCalendar"></CalendarCreateDialog>
    </div>
</template>

<script>
    import CalendarCreateDialog from './CalendarCreate'

    export default {
        components: {
            CalendarCreateDialog
        },
        name: "Calendar",
        data() {
            return {
                showNewCalendar: false,
                headers: [
                    {
                        text: this.$t('calendar.page.name'),
                        align: 'left',
                        sortable: true,
                        value: 'name'
                    },
                    {
                        text: this.$t('calendar.page.timezone'),
                        align: 'center',
                        sortable: true,
                        value: 'timezone'
                    },
                    {
                        text: this.$t('calendar.page.start'),
                        align: 'center',
                        sortable: true,
                        value: 'start'
                    },
                    {
                        text: this.$t('calendar.page.finish'),
                        align: 'center',
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
        computed: {
            calendars() {
                return this.$store.getters['calendar/list'];
            },
            loading() {
                return this.$store.getters['calendar/loading'];
            }
        },
        methods: {
            editItem(item) {
                this.$router.push({path: `/calendar/${item.id}`})
            },
            deleteItem(item) {

            },
            create() {
                this.showNewCalendar = true;
            }
        }
    }
</script>

<style scoped>

</style>