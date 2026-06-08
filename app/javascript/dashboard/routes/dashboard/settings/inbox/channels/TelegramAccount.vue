<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required, url } from '@vuelidate/validators';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    PageHeader,
    NextButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      gatewayUrl: '',
      webhookId: '',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
    }),
  },
  validations: {
    gatewayUrl: { required, url },
    webhookId: { required },
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        const inbox = await this.$store.dispatch('inboxes/createChannel', {
          channel: {
            type: 'telegram_account',
            gateway_url: this.gatewayUrl,
            webhook_id: this.webhookId,
          },
        });

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: inbox.id,
          },
        });
      } catch (error) {
        useAlert(
          error.message ||
            this.$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.API.ERROR_MESSAGE')
        );
      }
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.DESC')"
    />
    <form
      class="flex flex-wrap flex-col mx-0"
      @submit.prevent="createChannel()"
    >
      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.gatewayUrl.$error }">
          {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.GATEWAY_URL.LABEL') }}
          <input
            v-model="gatewayUrl"
            type="text"
            :placeholder="
              $t(
                'INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.GATEWAY_URL.PLACEHOLDER'
              )
            "
            @blur="v$.gatewayUrl.$touch"
          />
          <span v-if="v$.gatewayUrl.$error" class="message">
            {{
              $t(
                'INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.GATEWAY_URL.ERROR'
              )
            }}
          </span>
        </label>
        <p class="help-text">
          {{
            $t(
              'INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.GATEWAY_URL.SUBTITLE'
            )
          }}
        </p>
      </div>

      <div class="flex-shrink-0 flex-grow-0 mt-4">
        <label :class="{ error: v$.webhookId.$error }">
          {{ $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.WEBHOOK_ID.LABEL') }}
          <input
            v-model="webhookId"
            type="text"
            :placeholder="
              $t(
                'INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.WEBHOOK_ID.PLACEHOLDER'
              )
            "
            @blur="v$.webhookId.$touch"
          />
        </label>
        <p class="help-text">
          {{
            $t(
              'INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.WEBHOOK_ID.SUBTITLE'
            )
          }}
        </p>
      </div>

      <div class="w-full mt-4">
        <NextButton
          :is-loading="uiFlags.isCreating"
          type="submit"
          solid
          blue
          :label="
            $t('INBOX_MGMT.ADD.TELEGRAM_ACCOUNT_CHANNEL.SUBMIT_BUTTON')
          "
        />
      </div>
    </form>
  </div>
</template>
