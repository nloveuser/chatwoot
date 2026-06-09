<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required, numeric, minLength } from '@vuelidate/validators';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import axios from 'axios';
import auth from 'dashboard/api/auth';

const POLL_INTERVAL_MS = 2000;

export default {
  components: { PageHeader, NextButton },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      // step: 'form' | 'wait_code' | 'wait_password' | 'ready' | 'error'
      step: 'form',
      apiId: '',
      apiHash: '',
      phoneNumber: '',
      authCode: '',
      password: '',
      inboxId: null,
      isSubmitting: false,
      pollTimer: null,
      errorMessage: '',
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'inboxes/getUIFlags' }),
  },
  validations() {
    if (this.step === 'form') {
      return {
        apiId:       { required, numeric },
        apiHash:     { required, minLength: minLength(32) },
        phoneNumber: { required },
      };
    }
    if (this.step === 'wait_code') {
      return { authCode: { required } };
    }
    if (this.step === 'wait_password') {
      return { password: { required } };
    }
    return {};
  },
  beforeUnmount() {
    this.stopPolling();
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      this.isSubmitting = true;
      try {
        const inbox = await this.$store.dispatch('inboxes/createChannel', {
          channel: {
            type:         'telegram_account',
            api_id:       parseInt(this.apiId, 10),
            api_hash:     this.apiHash,
            phone_number: this.phoneNumber,
          },
        });
        this.inboxId = inbox.id;
        this.step = 'wait_code';
        this.startPolling();
      } catch (error) {
        useAlert(
          error.message ||
            this.$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.API.ERROR_MESSAGE')
        );
      } finally {
        this.isSubmitting = false;
      }
    },

    async submitCode() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      this.isSubmitting = true;
      try {
        await this.callAuthEndpoint('telegram_verify_code', { code: this.authCode });
        // State update comes via polling
      } catch (error) {
        useAlert(error.message || this.$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_CODE.ERROR'));
      } finally {
        this.isSubmitting = false;
      }
    },

    async submitPassword() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      this.isSubmitting = true;
      try {
        await this.callAuthEndpoint('telegram_verify_password', { password: this.password });
      } catch (error) {
        useAlert(error.message || this.$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_PASSWORD.ERROR'));
      } finally {
        this.isSubmitting = false;
      }
    },

    async callAuthEndpoint(action, payload) {
      const accountId = this.$store.getters['auth/getCurrentUser']?.account_id ||
        this.$route.params.accountId;
      const response = await axios.post(
        `/api/v1/accounts/${accountId}/inboxes/${this.inboxId}/${action}`,
        payload
      );
      return response.data;
    },

    startPolling() {
      this.pollTimer = setInterval(async () => {
        try {
          const accountId = this.$store.getters['auth/getCurrentUser']?.account_id ||
            this.$route.params.accountId;
          const response = await axios.get(
            `/api/v1/accounts/${accountId}/inboxes/${this.inboxId}/telegram_auth_state`
          );
          const { auth_state: state, error_message: errMsg } = response.data;

          if (state === 'ready') {
            this.stopPolling();
            this.step = 'ready';
          } else if (state === 'error') {
            this.stopPolling();
            this.step = 'error';
            this.errorMessage = errMsg || '';
          } else if (state !== this.step) {
            this.step = state;
          }
        } catch {
          // ignore transient poll errors
        }
      }, POLL_INTERVAL_MS);
    },

    stopPolling() {
      if (this.pollTimer) {
        clearInterval(this.pollTimer);
        this.pollTimer = null;
      }
    },

    finishSetup() {
      router.replace({
        name: 'settings_inboxes_add_agents',
        params: { page: 'new', inbox_id: this.inboxId },
      });
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <!-- Step 1: credentials form -->
    <template v-if="step === 'form'">
      <PageHeader
        :header-title="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.TITLE')"
        :header-content="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.DESC')"
      />
      <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel">
        <div class="flex-shrink-0 flex-grow-0">
          <label :class="{ error: v$.apiId.$error }">
            {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.API_ID.LABEL') }}
            <input
              v-model="apiId"
              type="text"
              :placeholder="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.API_ID.PLACEHOLDER')"
              @blur="v$.apiId.$touch"
            />
          </label>
          <p class="help-text">
            {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.API_ID.SUBTITLE') }}
          </p>
        </div>

        <div class="flex-shrink-0 flex-grow-0 mt-4">
          <label :class="{ error: v$.apiHash.$error }">
            {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.API_HASH.LABEL') }}
            <input
              v-model="apiHash"
              type="text"
              :placeholder="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.API_HASH.PLACEHOLDER')"
              @blur="v$.apiHash.$touch"
            />
          </label>
          <p class="help-text">
            {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.API_HASH.SUBTITLE') }}
          </p>
        </div>

        <div class="flex-shrink-0 flex-grow-0 mt-4">
          <label :class="{ error: v$.phoneNumber.$error }">
            {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.PHONE.LABEL') }}
            <input
              v-model="phoneNumber"
              type="text"
              :placeholder="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.PHONE.PLACEHOLDER')"
              @blur="v$.phoneNumber.$touch"
            />
          </label>
          <p class="help-text">
            {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.PHONE.SUBTITLE') }}
          </p>
        </div>

        <div class="w-full mt-4">
          <NextButton
            :is-loading="uiFlags.isCreating || isSubmitting"
            type="submit"
            solid
            blue
            :label="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.SUBMIT_BUTTON')"
          />
        </div>
      </form>
    </template>

    <!-- Step 2: waiting for / entering auth code -->
    <template v-else-if="step === 'pending' || step === 'wait_code'">
      <PageHeader
        :header-title="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_CODE.TITLE')"
        :header-content="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_CODE.DESC')"
      />
      <template v-if="step === 'wait_code'">
        <form class="flex flex-wrap flex-col mx-0" @submit.prevent="submitCode">
          <div class="flex-shrink-0 flex-grow-0">
            <label :class="{ error: v$.authCode?.$error }">
              {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_CODE.LABEL') }}
              <input
                v-model="authCode"
                type="text"
                autocomplete="one-time-code"
                :placeholder="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_CODE.PLACEHOLDER')"
                @blur="v$.authCode?.$touch"
              />
            </label>
          </div>
          <div class="w-full mt-4">
            <NextButton
              :is-loading="isSubmitting"
              type="submit"
              solid
              blue
              :label="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_CODE.SUBMIT')"
            />
          </div>
        </form>
      </template>
      <template v-else>
        <p class="mt-4 text-slate-600 dark:text-slate-300">
          {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_CODE.WAITING') }}
        </p>
      </template>
    </template>

    <!-- Step 3: 2FA password -->
    <template v-else-if="step === 'wait_password'">
      <PageHeader
        :header-title="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_PASSWORD.TITLE')"
        :header-content="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_PASSWORD.DESC')"
      />
      <form class="flex flex-wrap flex-col mx-0" @submit.prevent="submitPassword">
        <div class="flex-shrink-0 flex-grow-0">
          <label :class="{ error: v$.password?.$error }">
            {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_PASSWORD.LABEL') }}
            <input
              v-model="password"
              type="password"
              @blur="v$.password?.$touch"
            />
          </label>
        </div>
        <div class="w-full mt-4">
          <NextButton
            :is-loading="isSubmitting"
            type="submit"
            solid
            blue
            :label="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.VERIFY_PASSWORD.SUBMIT')"
          />
        </div>
      </form>
    </template>

    <!-- Step 4: connected -->
    <template v-else-if="step === 'ready'">
      <PageHeader
        :header-title="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.CONNECTED.TITLE')"
        :header-content="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.CONNECTED.DESC')"
      />
      <div class="w-full mt-4">
        <NextButton
          solid
          blue
          :label="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.CONNECTED.CONTINUE')"
          @click="finishSetup"
        />
      </div>
    </template>

    <!-- Error state -->
    <template v-else-if="step === 'error'">
      <PageHeader
        :header-title="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.ERROR.TITLE')"
        :header-content="errorMessage || $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.ERROR.DESC')"
      />
      <div class="w-full mt-4">
        <NextButton
          solid
          :label="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.ERROR.RETRY')"
          @click="step = 'form'"
        />
      </div>
    </template>
  </div>
</template>
