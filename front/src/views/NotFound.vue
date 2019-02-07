<template>
    <div>
        <div class="head__404">
            <div class="meta_404">

            </div>
            <div class="meta_404">

            </div>

        </div>
        <div class="text_404"></div>
    </div>
</template>

<script>
    export default {
        name: "NotFound"
    }
</script>

<style scoped>

    .head__404 {
        display: block;
        position: relative;
        width: 200px;
        margin: 10% auto 0;
        -webkit-animation: shvr 0.2s infinite;
        animation: shvr 0.2s infinite;
    }
    .head__404::after {
        content: '';
        box-sizing: border-box;
        width: 20px;
        height: 20px;
        background: #000;
        position: absolute;
        top: 30px;
        left: 25px;
        border-radius: 50%;
        box-shadow: 125px 0 0 #000;
        -webkit-animation: eye 2.5s infinite;
        animation: eye 2.5s infinite;
    }

    .meta_404 {
        position: relative;
        display: inline-block;
        background: #fff;
        width: 75px;
        height: 80px;
        border-radius: 50% 50% 50% 50%/45px 45px 45% 45%;
        -webkit-transform: rotate(45deg);
        transform: rotate(45deg);
    }
    .meta_404::after {
        content: '';
        box-sizing: border-box;
        position: absolute;
        border-bottom: 2px solid #fff;
        width: 70px;
        height: 50px;
        left: 0px;
        bottom: -10px;
        border-radius: 50%;
    }
    .meta_404::before {
        bottom: auto;
        box-sizing: border-box;
        top: -100px;
        -webkit-transform: rotate(45deg);
        transform: rotate(45deg);
        left: 0;
    }
    .meta_404:nth-of-type(2) {
        float: right;
        -webkit-transform: rotate(-45deg);
        transform: rotate(-45deg);
    }
    .meta_404:nth-of-type(2)::after {
        left: 5px;
        box-sizing: border-box;
    }
    .meta_404:nth-of-type(3) {
        display: none;
    }

    .text_404 {
        margin-top: 100px;
        text-align: center;
        color: #fff;
    }
    .text_404::before {
        content: '404';
        font-size: 80px;
        box-sizing: border-box;
        font-weight: 800;
        display: block;
        margin-bottom: 10px;
    }
    .text_404::after {
        content: 'Got lost? How.....?  why.....?  Ahhhh....';
        color: #1EA7AB;
        width: 120px;
        font-size: 30px;
        box-sizing: border-box;
        overflow: hidden;
        display: inline-block;
        white-space: nowrap;
        -webkit-animation: text-show 2s infinite steps(3);
        animation: text-show 2s infinite steps(3);
    }
    @-webkit-keyframes eye {
        0% ,30% , 55%, 90% , 100% {
            -webkit-transform: translate(0, 0);
            transform: translate(0, 0);
        }
        10%, 25% {
            -webkit-transform: translate(0, 20px);
            transform: translate(0, 20px);
        }
        65% {
            -webkit-transform: translate(-20px, 0);
            transform: translate(-20px, 0);
        }
        80% {
            -webkit-transform: translate(20px, 0);
            transform: translate(20px, 0);
        }
    }
    @keyframes eye {
        0% ,30% , 55%, 90% , 100% {
            -webkit-transform: translate(0, 0);
            transform: translate(0, 0);
        }
        10%, 25% {
            -webkit-transform: translate(0, 20px);
            transform: translate(0, 20px);
        }
        65% {
            -webkit-transform: translate(-20px, 0);
            transform: translate(-20px, 0);
        }
        80% {
            -webkit-transform: translate(20px, 0);
            transform: translate(20px, 0);
        }
    }
    @-webkit-keyframes shvr {
        0% {
            -webkit-transform: translate(1px, 1em);
            transform: translate(1px, 1em);
        }
        50% {
            -webkit-transform: translate(0, 1em);
            transform: translate(0, 1em);
        }
        100% {
            -webkit-transform: translate(-1px, 1em);
            transform: translate(-1px, 1em);
        }
    }
    @keyframes shvr {
        0% {
            -webkit-transform: translate(1px, 1em);
            transform: translate(1px, 1em);
        }
        50% {
            -webkit-transform: translate(0, 1em);
            transform: translate(0, 1em);
        }
        100% {
            -webkit-transform: translate(-1px, 1em);
            transform: translate(-1px, 1em);
        }
    }
    @-webkit-keyframes text-show {
        to {
            text-indent: -373px;
        }
    }
    @keyframes text-show {
        to {
            text-indent: -373px;
        }
    }

</style>