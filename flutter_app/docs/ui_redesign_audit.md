# UI/UX Audit Checklist (GigMe)

## 1) Экранный аудит

### Публичный контур
- [x] `LandingScreen`: визуально сильный, но перегружен эффектами на слабых устройствах.
- [x] `AuthScreen`: смешаны режимы входа, много технического текста, нет единой иерархии CTA.

### Основной пользовательский контур
- [x] `FeedScreen` + `FeedList` + `EventCardTile`: ранее был контраст/читабельность, улучшено; нужен единый state-pattern.
- [x] `MapScreen`: карта функциональна, но CTA и состояния не в дизайн-системе.
- [x] `CreateEventScreen`: длинная форма без секционного разбиения, высокая когнитивная нагрузка.
- [x] `EventDetailsScreen`: много действий в одном столбце, вторичные действия визуально конкурируют с главным.
- [x] `ProfileScreen`: смешаны пользовательские и админ-действия, ранее слабая визуальная иерархия.
- [x] `MyTicketsPage` / `PurchaseTicketFlow`: состояния и блоки не унифицированы.

### Админ-контур
- [x] `AdminScreen` + `admin_*` pages: исторически смешанные стили, частично англоязычные подписи, кнопки с низкой заметностью.

## 2) Основные UX-проблемы
- [x] Перегруз интерфейсов длинными формами и плотными списками без секций.
- [x] Несистемные состояния `loading/empty/error/success` между экранами.
- [x] Низкая однородность CTA (где-то `FilledButton`, где-то `OutlinedButton`, где-то `AppButton`).
- [x] Частичная локализация (RU/EN микс).
- [x] Навигация на больших экранах менее очевидна, чем на mobile.
- [x] Разнородная визуальная иерархия (заголовки, подзаголовки, вторичные действия).

## 3) Новая IA (Information Architecture)

### Глобальная навигация
- Mobile: `BottomNavigationBar` на 4 пункта: `Лента`, `Карта`, `Создать`, `Профиль`.
- Desktop/Web: `NavigationRail` слева с теми же 4 пунктами.
- Отдельные контуры:
  - Публичный: `Landing`, `Auth`.
  - Пользовательский: `Feed`, `Map`, `Create`, `Profile`, `Tickets`, `EventDetails`.
  - Админский: `Admin` + `Orders/Scanner/Products/Promos/Stats`.

### Layout-паттерны
- Pattern A (List + Filters): `Header -> Quick actions -> Filters -> Content list`.
- Pattern B (Map): `Header -> Floating map controls -> Bottom details sheet`.
- Pattern C (Form wizard-lite): `Header -> SectionCard blocks -> Sticky primary CTA`.
- Pattern D (Detail page): `Hero summary -> Primary CTA -> Secondary actions -> Structured sections`.

## 4) Редизайн-план по этапам
- [x] Токены и тема (light/dark, typography, spacing, shape, motion).
- [x] Базовые reusable-компоненты (`SectionCard`, `InputField`, `AppStates`, standardized buttons).
- [x] Адаптивная навигация (`BottomNav` + `NavigationRail`).
- [x] UI Preview экран `/space_app/dev/ui_preview`.
- [ ] Полный перевод всех экранов на новые компоненты (в процессе).
- [ ] Финальная чистка микрокопирайтов и локализация без hardcoded строк (в процессе).

## 5) Критерии проверки после миграции каждого экрана
- [ ] Один главный CTA, вторичные действия визуально слабее.
- [ ] Все состояния присутствуют и выглядят системно.
- [ ] Минимальный touch target >= 44 px.
- [ ] Контраст текста и интерактивных элементов в норме.
- [ ] Нет “визуального шума” (единые отступы, радиусы, тени).
