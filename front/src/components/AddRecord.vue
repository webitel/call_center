<template>
    <v-btn
            fixed
            dark
            fab
            bottom
            right
            color="pink"
            @click="(e) => click(e)"
    >
        <v-icon>add</v-icon>
    </v-btn>
</template>

<script>
    export default {
        name: "AddRecord",
        props: {
            click: Function
        }
    }
</script>

<style scoped>

</style>