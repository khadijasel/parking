<script setup>
import { computed } from 'vue'

const props = defineProps({
  title: {
    type: String,
    default: 'Metric',
  },
  value: {
    type: [String, Number],
    default: '0',
  },
  subtitle: {
    type: String,
    default: '',
  },
  badgeLabel: {
    type: String,
    default: '',
  },
  badgeTone: {
    type: String,
    default: 'neutral',
    validator: (value) => ['neutral', 'danger', 'info', 'success', 'warning'].includes(value),
  },
})

const badgeToneClasses = {
  neutral: 'bg-surface-container text-on-surface-variant',
  danger: 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-200',
  info: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-200',
  success: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-200',
  warning: 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-200',
}

const badgeClass = computed(() => badgeToneClasses[props.badgeTone])
</script>

<template>
  <article class="surface-card p-5">
    <div class="flex items-start justify-between gap-3">
      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-outline">{{ title }}</p>
        <p class="mt-3 font-headline text-3xl font-extrabold text-on-surface">{{ value }}</p>
      </div>

      <span
        v-if="badgeLabel"
        class="rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-[0.08em]"
        :class="badgeClass"
      >
        {{ badgeLabel }}
      </span>
    </div>

    <p v-if="subtitle" class="mt-3 text-xs font-medium text-on-surface-variant">{{ subtitle }}</p>
  </article>
</template>
