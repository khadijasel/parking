<script setup>
import { ref } from 'vue'
import { RouterView } from 'vue-router'
import OwnerSidebar from '@/components/layout/OwnerSidebar.vue'
import OwnerTopbar from '@/components/layout/OwnerTopbar.vue'

const isSidebarOpen = ref(false)

const toggleSidebar = () => {
  isSidebarOpen.value = !isSidebarOpen.value
}

const closeSidebar = () => {
  isSidebarOpen.value = false
}
</script>

<template>
  <div class="min-h-screen bg-surface text-on-surface">
    <div
      v-if="isSidebarOpen"
      class="fixed inset-0 z-40 bg-on-surface/30 lg:hidden"
      @click="closeSidebar"
    />

    <OwnerSidebar :is-open="isSidebarOpen" @close="closeSidebar" />

    <div class="lg:pl-72">
      <OwnerTopbar @toggle-sidebar="toggleSidebar" />

      <main class="h-screen overflow-y-auto px-4 pb-12 pt-20 sm:px-6 lg:px-10">
        <RouterView />
      </main>
    </div>
  </div>
</template>
