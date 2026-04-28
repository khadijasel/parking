<script setup>
import { computed } from 'vue'

const props = defineProps({
  currentPage: {
    type: Number,
    default: 1,
  },
  totalPages: {
    type: Number,
    default: 1,
  },
})

const emit = defineEmits(['update:page'])

const canGoPrev = computed(() => props.currentPage > 1)
const canGoNext = computed(() => props.currentPage < props.totalPages)

const goPrev = () => {
  if (!canGoPrev.value) {
    return
  }

  emit('update:page', props.currentPage - 1)
}

const goNext = () => {
  if (!canGoNext.value) {
    return
  }

  emit('update:page', props.currentPage + 1)
}
</script>

<template>
  <div class="flex items-center justify-between gap-3">
    <p class="text-xs font-medium text-on-surface-variant">
      Page {{ currentPage }} sur {{ totalPages }}
    </p>

    <div class="flex items-center gap-2">
      <button
        type="button"
        class="rounded-lg bg-surface-container px-3 py-1.5 text-xs font-semibold text-on-surface transition-colors hover:bg-surface-container-high disabled:cursor-not-allowed disabled:opacity-40"
        :disabled="!canGoPrev"
        @click="goPrev"
      >
        Precedent
      </button>
      <button
        type="button"
        class="rounded-lg bg-surface-container px-3 py-1.5 text-xs font-semibold text-on-surface transition-colors hover:bg-surface-container-high disabled:cursor-not-allowed disabled:opacity-40"
        :disabled="!canGoNext"
        @click="goNext"
      >
        Suivant
      </button>
    </div>
  </div>
</template>
