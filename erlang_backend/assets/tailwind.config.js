/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "../lib/agent_backend_web/**/*.heex",
    "../lib/agent_backend_web/**/*.ex",
    "../assets/js/**/*.js",
    "../assets/css/**/*.css"
  ],
  safelist: [
    // Core layout & colors used in the minimal chat UI
    'h-screen', 'h-dvh', 'flex', 'flex-1', 'flex-col', 'flex-wrap', 'items-center', 'justify-center', 'justify-between', 'justify-start', 'justify-end',
    'max-w-2xl', 'max-w-xs', 'max-w-sm', 'max-w-[80%]', 'w-full', 'w-6', 'w-10', 'h-6', 'h-10', 'mx-auto',
    'overflow-hidden', 'overflow-y-auto',
    'px-1', 'px-3', 'px-4', 'py-1', 'py-2.5', 'py-3', 'py-6',
    'gap-1.5', 'gap-2', 'space-y-5', 'mt-1.5', 'mt-2.5', 'mb-3',
    'text-xs', 'text-sm', 'text-xl', 'text-3xl', 'font-medium', 'font-semibold', 'tracking-tight', 'leading-relaxed',
    'rounded', 'rounded-md', 'rounded-2xl', 'rounded-full',
    'border', 'border-b', 'border-t', 'border-zinc-800', 'border-zinc-700',
    'bg-zinc-950', 'bg-zinc-900', 'bg-zinc-800', 'bg-white', 'bg-white/10', 'bg-current',
    'text-zinc-950', 'text-zinc-200', 'text-zinc-300', 'text-zinc-400', 'text-zinc-500', 'text-zinc-100', 'text-zinc-600', 'text-zinc-700',
    'placeholder:text-zinc-500',
    'focus:border-zinc-700', 'focus:outline-none',
    'hover:bg-zinc-800', 'hover:text-zinc-200', 'hover:text-zinc-300', 'active:bg-zinc-950',
    'disabled:opacity-60',
    'hidden',
    'border-amber-900/50', 'bg-amber-950/40', 'text-amber-200/80',
    'transition-colors', 'transition-all', 'transition-opacity',
    'backdrop-blur', 'backdrop-blur-sm',
    'animate-bounce', 'animate-pulse',
    'whitespace-pre-wrap',
    // sky accent
    'bg-sky-500/15', 'text-sky-300', 'text-sky-400/90', 'text-sky-500/70',
    'hover:text-sky-200', 'hover:text-sky-200/90', 'hover:border-sky-500/30', 'hover:bg-sky-50',
    'focus:border-sky-500/40', 'focus:ring-1', 'focus:ring-sky-500/20',
    // error state
    'border-rose-900/50', 'border-rose-900/40', 'bg-rose-950/30', 'bg-rose-950/50',
    'text-rose-200/90', 'text-rose-100', 'hover:bg-rose-950/50', 'hover:text-rose-100',
    'bg-zinc-900/80', 'bg-zinc-950/95', 'border-zinc-800/80',
    // arbitrary values used in loading dots
    'bg-zinc-950/80',
    '[animation-delay:-0.2s]',
    '[animation-delay:-0.1s]',
    'active:scale-95',
    // Markdown (prose) styling
    'prose', 'prose-invert', 'prose-sm', 'max-w-none'
  ],
  theme: {
    extend: {}
  },
  plugins: [
    require('@tailwindcss/typography')
  ]
}
