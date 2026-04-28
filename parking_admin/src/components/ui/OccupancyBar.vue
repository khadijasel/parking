<script setup>
import { computed } from 'vue'

const props = defineProps({
  label: {
    type: String,
    default: 'Zone',
  },
  value: {
    type: Number,
    default: 0,
  },
  tone: {
    type: String,
    default: 'neutral',
    validator: (value) => ['danger', 'info', 'neutral'].includes(value),
  },
})

const toneClassMap = {
  danger: 'bg-red-500',
  info: 'bg-primary',
  neutral: 'bg-outline-variant',
}

const trackClassMap = {
  danger: 'bg-red-100 dark:bg-red-900/20',
  info: 'bg-blue-100 dark:bg-blue-900/20',
  neutral: 'bg-surface-container',
}

const segments = 20

const clampedValue = computed(() => {
  if (props.value < 0) {
    return 0
  }

  if (props.value > 100) {
    return 100
  }

  return props.value
})

const barClass = computed(() => toneClassMap[props.tone])
const trackClass = computed(() => trackClassMap[props.tone])

const activeSegments = computed(() => {
  return Math.round((clampedValue.value / 100) * segments)
})

const segmentItems = computed(() => {
  return Array.from({ length: segments }, (_, index) => {
    const toneClass = index < activeSegments.value ? barClass.value : trackClass.value

    return {
      id: index,
      toneClass,
    }
  })
})
</script>

<template>
  <div class="space-y-2">
    <div class="flex items-center justify-between">
      <p class="text-sm font-semibold text-on-surface">{{ label }}</p>
      <p class="text-sm font-bold text-on-surface">{{ clampedValue }}%</p>
    </div>

    <div class="grid grid-cols-[repeat(20,minmax(0,1fr))] gap-1">
      <span
        v-for="segment in segmentItems"
        :key="segment.id"
        class="h-2 rounded-full transition-colors duration-300"
        :class="segment.toneClass"
      />
    </div>
  </div>
</template>
