<script setup>
import { computed, ref } from 'vue'
import { useDark, useToggle } from '@vueuse/core'

const emit = defineEmits(['toggle-sidebar'])

const search = ref('')
const isDark = useDark({ selector: 'html' })
const toggleDark = useToggle(isDark)

const darkIcon = computed(() => {
  if (isDark.value) {
    return 'light_mode'
  }

  return 'dark_mode'
})

const statusText = computed(() => {
  if (isDark.value) {
    return 'Mode nuit actif'
  }

  return 'Espace proprietaire actif'
})

const onToggleSidebar = () => {
  emit('toggle-sidebar')
}

const onToggleDark = () => {
  toggleDark()
}
</script>

<template>
  <header
    class="fixed right-0 top-0 z-40 flex h-16 w-full items-center justify-between bg-surface-container-lowest/80 px-4 backdrop-blur-xl shadow-sm dark:bg-slate-950/85 dark:shadow-none lg:w-[calc(100%-18rem)] lg:px-8"
  >
    <div class="flex w-full items-center gap-3 lg:w-1/2">
      <button
        type="button"
        class="rounded-lg p-2 text-on-surface-variant hover:bg-surface-container lg:hidden"
        @click="onToggleSidebar"
      >
        <span class="material-symbols-outlined text-[22px]">menu</span>
      </button>

      <div class="relative w-full max-w-lg">
        <span
          class="material-symbols-outlined pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-outline"
        >
          search
        </span>
        <input
          v-model="search"
          type="text"
          placeholder="Rechercher places, voies, capteurs..."
          class="w-full rounded-full bg-surface-container-low py-2 pl-10 pr-4 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30 dark:bg-slate-800 dark:text-slate-100 dark:placeholder:text-slate-400"
        />
      </div>
    </div>

    <div class="hidden items-center gap-4 lg:flex">
      <div class="flex items-center gap-2 rounded-full bg-surface-container-low px-3 py-1.5">
        <span class="h-2 w-2 rounded-full bg-emerald-500" />
        <span class="text-xs font-semibold text-on-surface-variant">{{ statusText }}</span>
      </div>

      <button
        type="button"
        class="rounded-lg p-2 text-on-surface-variant transition-colors hover:bg-surface-container"
      >
        <span class="material-symbols-outlined text-[20px]">notifications</span>
      </button>

      <button
        type="button"
        class="rounded-lg p-2 text-on-surface-variant transition-colors hover:bg-surface-container"
        @click="onToggleDark"
      >
        <span class="material-symbols-outlined text-[20px]">{{ darkIcon }}</span>
      </button>

      <div class="h-8 w-px bg-outline-variant/40" />

      <div class="text-right">
        <p class="font-headline text-xs font-bold text-on-surface">Owner User</p>
        <p class="text-[11px] text-outline">Proprietaire de parking</p>
      </div>
      <div class="flex h-9 w-9 items-center justify-center rounded-full bg-primary-fixed text-xs font-bold text-primary">
        OW
      </div>
    </div>
  </header>
</template>
