<template>
    <v-text-field
            label="Search"
            single-line
            v-model="searchValue"
            @input="throttledSearch"

    ></v-text-field>
</template>

<script>
    import throttle from '../core/throttle'
    export default {
        name: "throttleSearch",
        data() {
            return {
                searchValue: this.$props.currentValue || ""
            }
        },
        computed: {
            throttledSearch() {
                return throttle(this.onSearch, 500);
            }
        },
        methods: {
            onSearch() {
                this.$store.dispatch(this.$props.dispatchName, this.searchValue)
            }
        },
        props: {
            dispatchName: String,
            currentValue: String
        }
    }
</script>

<style scoped>

</style>