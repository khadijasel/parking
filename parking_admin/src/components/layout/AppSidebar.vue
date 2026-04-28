<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useParkingsStore } from '@/stores/parkings'

const props = defineProps({
  isOpen: {
    type: Boolean,
    default: false,
  },
})

const emit = defineEmits(['close'])

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const parkingsStore = useParkingsStore()

const navItems = [
  {
    name: 'Tableau de bord',
    icon: 'dashboard',
    to: '/dashboard',
  },
  {
    name: 'Carte en direct',
    icon: 'map',
    to: '/live-map',
  },
  {
    name: 'Historique global',
    icon: 'insights',
    to: '/analytics',
  },
  {
    name: 'Controle d acces',
    icon: 'admin_panel_settings',
    to: '/access-control',
  },
]

const sidebarClass = computed(() => {
  if (props.isOpen) {
    return 'translate-x-0'
  }

  return '-translate-x-full lg:translate-x-0'
})

const isActive = (path) => route.path === path

const linkClass = (path) => {
  if (isActive(path)) {
    return 'sidebar-link bg-surface-container-lowest text-primary shadow-sm dark:bg-slate-800 dark:text-blue-300'
  }

  return 'sidebar-link text-on-surface-variant hover:bg-surface-container dark:text-slate-300 dark:hover:bg-slate-800'
}

const navigate = async (path) => {
  if (route.path !== path) {
    await router.push(path)
  }

  emit('close')
}

const closeSidebar = () => {
  emit('close')
}

const onAddParking = async () => {
  parkingsStore.openAddPanel()

  if (route.path !== '/live-map') {
    await router.push('/live-map')
  }

  emit('close')
}

const onLogout = async () => {
  await authStore.logout()
  emit('close')
  await router.replace('/auth/admin')
}
</script>

<template>
  <aside
    class="fixed left-0 top-0 z-50 flex h-screen w-72 flex-col bg-surface-container-low px-6 py-8 transition-transform duration-300 dark:bg-slate-900"
    :class="sidebarClass"
  >
    <div class="mb-10 px-2">
      <h1 class="font-headline text-xl font-extrabold tracking-tight text-primary">Fluid Architect</h1>
      <p class="mt-1 text-xs font-semibold uppercase tracking-[0.2em] text-outline">Console admin</p>
    </div>

    <nav class="flex flex-1 flex-col gap-1">
      <button
        v-for="item in navItems"
        :key="item.to"
        type="button"
        :class="linkClass(item.to)"
        @click="navigate(item.to)"
      >
        <span class="material-symbols-outlined text-[20px]">{{ item.icon }}</span>
        <span>{{ item.name }}</span>
      </button>
    </nav>

    <div class="mt-6 flex flex-col gap-2">
      <button
        type="button"
        class="primary-cta flex items-center justify-center gap-2"
        @click="onAddParking"
      >
        <span class="material-symbols-outlined text-[18px]">add</span>
        <span>Ajouter un parking</span>
      </button>

      <button
        type="button"
        class="sidebar-link justify-start text-on-surface-variant hover:bg-surface-container"
      >
        <span class="material-symbols-outlined text-[20px]">help</span>
        <span>Aide</span>
      </button>

      <button
        type="button"
        class="sidebar-link justify-start text-on-surface-variant hover:bg-surface-container"
        @click="onLogout"
      >
        <span class="material-symbols-outlined text-[20px]">logout</span>
        <span>Deconnexion</span>
      </button>
    </div>

    <button
      type="button"
      class="absolute right-4 top-4 rounded-lg p-2 text-on-surface-variant hover:bg-surface-container lg:hidden"
      @click="closeSidebar"
    >
      <span class="material-symbols-outlined text-[20px]">close</span>
    </button>
  </aside>
</template>
