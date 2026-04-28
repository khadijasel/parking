<script setup>
import { computed } from 'vue'

const props = defineProps({
  label: {
    type: String,
    default: 'Unknown',
  },
  tone: {
    type: String,
    default: 'neutral',
    validator: (value) => ['success', 'info', 'warning', 'danger', 'neutral'].includes(value),
  },
})

const toneClassMap = {
  success: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-200',
  info: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-200',
  warning: 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-200',
  danger: 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-200',
  neutral: 'bg-surface-container text-on-surface-variant',
}

const badgeClass = computed(() => toneClassMap[props.tone])
</script>

<template>
  <span
    class="inline-flex items-center rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.08em]"
    :class="badgeClass"
  >
    {{ label }}
  </span>
</template>
