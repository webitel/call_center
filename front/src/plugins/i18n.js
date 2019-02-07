import Vue from 'vue'
import VueI18n from 'vue-i18n'
import en from '../i18n/en'

Vue.use(VueI18n);

const messages = {
    en
};

const i18n = new VueI18n({
    locale: 'en', // set locale
    messages,
});

export default i18n;