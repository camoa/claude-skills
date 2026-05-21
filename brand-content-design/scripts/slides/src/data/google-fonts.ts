/**
 * Curated snapshot of common Google Fonts family names.
 *
 * Used by `font-classifier.ts` for a membership check — Google Slides renders
 * only families in the Google Fonts catalogue. This is a SNAPSHOT of the most
 * widely-used families, not the full ~1800-family catalogue; a partial list
 * still functions correctly (an unknown family is treated as custom, which is
 * the safe fallback — it triggers the display-text-as-image bake). Refresh from
 * the Google Fonts Developer API when broader coverage is needed.
 */
export const GOOGLE_FONTS: readonly string[] = [
  // Sans-serif workhorses
  'Roboto', 'Open Sans', 'Lato', 'Montserrat', 'Inter', 'Poppins', 'Raleway',
  'Nunito', 'Nunito Sans', 'Work Sans', 'Rubik', 'Mukta', 'Noto Sans',
  'Roboto Condensed', 'Ubuntu', 'PT Sans', 'Oswald', 'Source Sans 3',
  'Source Sans Pro', 'Mulish', 'Karla', 'Barlow', 'DM Sans', 'Manrope',
  'Fira Sans', 'Josefin Sans', 'Libre Franklin', 'Hind', 'Heebo',
  'Titillium Web', 'Cabin', 'Dosis', 'Quicksand', 'Archivo', 'Archivo Narrow',
  'Asap', 'Catamaran', 'Exo 2', 'Figtree', 'Jost', 'Kanit', 'Lexend',
  'Maven Pro', 'Outfit', 'Overpass', 'Plus Jakarta Sans', 'Prompt',
  'Public Sans', 'Red Hat Display', 'Red Hat Text', 'Saira', 'Sora',
  'Urbanist', 'Albert Sans', 'Be Vietnam Pro', 'Hanken Grotesk',
  'Instrument Sans', 'Onest', 'Schibsted Grotesk', 'Space Grotesk',
  'IBM Plex Sans', 'PT Sans Narrow',
  // Serif
  'Merriweather', 'Playfair Display', 'Lora', 'PT Serif', 'Roboto Slab',
  'Noto Serif', 'Source Serif 4', 'Crimson Text', 'EB Garamond', 'Bitter',
  'Arvo', 'Cormorant Garamond', 'Spectral', 'Zilla Slab', 'Libre Baskerville',
  'IBM Plex Serif', 'DM Serif Display', 'DM Serif Text', 'Slabo 27px',
  // Monospace
  'Roboto Mono', 'IBM Plex Mono', 'Space Mono', 'JetBrains Mono', 'Fira Code',
  'Source Code Pro', 'Inconsolata',
  // Display / decorative
  'Anton', 'Bebas Neue', 'Abril Fatface', 'Pacifico', 'Dancing Script',
  'Caveat', 'Lobster', 'Comfortaa', 'Righteous', 'Permanent Marker',
  'Shadows Into Light', 'Amatic SC', 'Courgette', 'Great Vibes',
];
