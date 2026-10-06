---
version: 1.1.2
name: app-ui-mvvm
description: "Expert for App UI MVVM pattern and dependency injection - ObservableObject, RelayCommand, AppBuilder, service registration, and DI. Use this skill whenever the user wants to create a ViewModel, bind data to UI elements, set up dependency injection, register services, implement commands for button actions, use [ObservableProperty] or [RelayCommand] attributes, create an AppBuilder, or structure their Unity App UI project with the MVVM architecture pattern. Also trigger when the user asks about data binding in UXML, property change notifications, or service lifetimes (transient, singleton, scoped)."
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# App UI MVVM & Dependency Injection Expert

## Overview

The MVVM (Model-View-ViewModel) pattern is a design pattern that separates user interface from business logic. Combined with Dependency Injection (DI), it creates a powerful architecture for building maintainable, testable, and scalable applications using Unity's UI Toolkit.

## Key Namespaces

- `Unity.AppUI.MVVM` - Core MVVM classes and DI
- `Unity.Properties` - Property attributes and binding support

## MVVM + Dependency Injection Architecture

```
┌─────────────────────────────────────────────┐
│            UIToolkitAppBuilder              │
│  (Configures app and services)              │
└──────────────────┬──────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        v                     v
   ┌─────────┐         ┌──────────────┐
   │   App   │         │ Service      │
   │         │         │ Collection   │
   └────┬────┘         └──────────────┘
        │
        v
   ┌──────────────────┐
   │   Views (UI)     │◄──── Data Binding ◄─── ViewModels
   │                  │      Commands           (Observable,
   └──────────────────┘                         RelayCommand)
```

## Common Patterns

### 1. Observable Properties
Mark ViewModel properties with `[ObservableProperty]` to automatically generate property change notifications:

```csharp
[ObservableObject]
public partial class MyViewModel
{
    [ObservableProperty]
    private string _name;
}
```

### 2. Relay Commands
Use `[RelayCommand]` attributes to auto-generate command properties:

```csharp
[ObservableObject]
public partial class MyViewModel
{
    [RelayCommand]
    private void SaveData()
    {
        // Execute command logic
    }
}
```

### 3. Service Registration
Register services in `AppBuilder.OnConfiguringApp()`:

```csharp
appBuilder.services.AddSingleton<IMyService, MyService>();
appBuilder.services.AddTransient<MyViewModel>();
```

### 4. Service Injection
Inject services via constructor or `[Service]` attribute:

```csharp
[ObservableObject]
public partial class MyViewModel
{
    [Service]
    public IMyService MyService { get; set; }
}
```

### 5. Dependent Properties
Use `[AlsoNotifyChangeFor]` to notify dependent properties:

```csharp
[ObservableObject]
public partial class MyViewModel
{
    [ObservableProperty]
    [AlsoNotifyChangeFor(nameof(IsNameEmpty))]
    private string _name;

    public bool IsNameEmpty => string.IsNullOrEmpty(Name);
}
```

## Best Practices

1. **Class Declaration**: Classes with `[ObservableObject]` must be `partial`
2. **Field Naming**: Observable fields must be private with underscore prefix (`_fieldName`)
3. **Constructor Injection**: Prefer constructor injection for required dependencies
4. **Property Injection**: Use `[Service]` attribute for optional dependencies
5. **Command Naming**: Method names for `[RelayCommand]` should describe the action (e.g., `SaveData`, `DeleteItem`)
6. **Separation of Concerns**: Keep business logic in ViewModels, UI logic in Views
7. **Service Lifetimes**:
   - Use `AddSingleton` for stateless services (loggers, factories)
   - Use `AddTransient` for stateful services (ViewModels, Pages)
   - Use `AddScoped` for services tied to a specific scope

## Command Patterns

### Simple Commands
```csharp
[RelayCommand]
void DoSomething() { }
```

### Commands with Parameters
```csharp
[RelayCommand]
void DoSomethingWith(string parameter) { }
```

### Async Commands
```csharp
[RelayCommand]
async Task DoSomethingAsync()
{
    await Task.Delay(1000);
}
```

### Conditional Commands
```csharp
[RelayCommand(CanExecute = nameof(CanSave))]
void Save() { }

private bool CanSave => !string.IsNullOrEmpty(Name);
```

## UI Binding

ViewModels expose observable properties and commands that bind to UI elements:

```xml
<ui:Button title="Save">
    <Bindings>
        <ui:DataBinding property="clickable.command" binding-mode="ToTarget" data-source-path="SaveCommand"/>
        <ui:DataBinding property="enabledSelf" binding-mode="ToTarget" data-source-path="CanSave"/>
    </Bindings>
</ui:Button>
```

## Related Features

- **State Management**: Redux-like pattern for complex state
- **Navigation**: Structured page navigation with parameters
- **Data Binding**: Automatic UI updates from ViewModel changes
- **Commands**: User action handling via RelayCommand

## Reference Documentation

Consult [reference.md](reference.md) when you need exact API signatures for ObservableObject, RelayCommand, AppBuilder, or service container methods, full attribute parameter lists, advanced DI patterns like scoped lifetimes, or details on IDependencyInjectionListener and [CreateProperty]. See [examples/](examples/) for complete MVVM app setups with multiple ViewModels and services.
