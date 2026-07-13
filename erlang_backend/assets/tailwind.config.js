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
    'h-screen', 'flex', 'flex-1', 'flex-col', 'flex-wrap', 'items-center', 'justify-center', 'justify-between', 'justify-start', 'justify-end',
    'max-w-2xl', 'max-w-xs', 'max-w-[80%]', 'w-full', 'w-6', 'w-10', 'h-6', 'h-10', 'mx-auto',
    'overflow-hidden', 'overflow-y-auto',
    'px-1', 'px-3', 'px-4', 'py-1', 'py-2.5', 'py-3', 'py-6',
    'gap-1.5', 'gap-2', 'space-y-5', 'mt-1.5', 'mt-2.5', 'mb-3',
    'text-xs', 'text-sm', 'text-xl', 'text-3xl', 'font-medium', 'font-semibold', 'tracking-tight', 'leading-relaxed',
    'rounded', 'rounded-2xl', 'rounded-full',
    'border', 'border-b', 'border-t', 'border-zinc-800', 'border-zinc-700',
    'bg-zinc-950', 'bg-zinc-900', 'bg-zinc-800', 'bg-white', 'bg-white/10', 'bg-current',
    'text-zinc-950', 'text-zinc-200', 'text-zinc-300', 'text-zinc-400', 'text-zinc-500', 'text-zinc-100',
    'placeholder:text-zinc-500',
    'focus:border-zinc-700', 'focus:outline-none',
    'hover:bg-zinc-800', 'hover:text-zinc-200', 'hover:text-zinc-300', 'active:bg-zinc-950',
    'disabled:opacity-60',
    'hidden',
    'border-amber-900/50', 'bg-amber-950/40', 'text-amber-200/80',
    'transition-colors',
    'backdrop-blur',
    'animate-bounce',
    'whitespace-pre-wrap',
    // arbitrary values used in loading dots
    'bg-zinc-950/80',
    '[animation-delay:-0.2s]',
    '[animation-delay:-0.1s]',
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
