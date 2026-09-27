# Manisa Design Language — «خانهٔ آرام»

## Character

Quiet confidence, immediate feedback and human Persian language. The interface should feel like part of the home, not an installer console.

## Foundations

- **Ink** `#172322`: primary text and decisive actions.
- **Manisa Teal** `#087A78`: identity, selected state and confirmed connectivity.
- **Mint** `#D9F3EF`: selected containers and positive calm feedback.
- **Canvas** `#F5F8F6`: warm neutral background.
- **Surface** `#FCFEFD`: cards and controls.
- **Amber** `#9B5C00`: attention/stale, never generic decoration.
- **Red** `#BA1A1A`: destructive action and confirmed failures only.

Use color as redundant state support, never as the sole signal.

## Shape and spacing

- 4dp base grid; primary gaps 8/12/16/24/32.
- 22dp cards, 16dp inputs/buttons, pill navigation indicator.
- Cards use a fine border rather than heavy shadow; smart-home control should feel stable, not floating.
- Minimum interactive target 48×48dp; primary actions 54dp high.

## Type

Vazirmatn-first with Noto Sans Arabic/Roboto fallback. Headlines are bold but compact; body copy has generous 1.6 line height for Persian readability. Numerals are presented in Persian in user-facing values.

## Component grammar

- **Home health:** one concise status line. Healthy, recovering and needs-attention variants.
- **Section header:** icon + label + optional count/action. Never a decorative heading alone.
- **Device card:** identity → truthful availability → primary control → progressive details → contextual menu.
- **State badge:** icon + text. «روشن»، «خاموش»، «در دسترس نیست»، «نیاز به به‌روزرسانی».
- **Trust notice:** short surface for local execution/recovery rules, with technical detail behind support.
- **Empty state:** one explanation and one next action; no dead-end illustration requirement.

## Motion

150–220ms for selection and expansion. Pending control may pulse subtly; final color/state must wait for confirmed readback. Respect reduced-motion settings. No splash animation may delay first control.

## Voice

Direct, calm, specific and non-technical. Say what happened, what is known and what the user can do next. Prefer «وضعیت هنوز دریافت نشده» to «خطای Attribute Read» and «شبکهٔ خانه» to ambiguous «شبکه».

## Accessibility

WCAG AA contrast, semantic labels for non-text controls, text scaling to 200%, no hidden essential gestures, and explicit confirmation for removal/factory-reset-adjacent actions.
