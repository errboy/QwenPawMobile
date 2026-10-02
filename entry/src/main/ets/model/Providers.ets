/**
 * Model picker rules, ported from the desktop console's model selector.
 *
 * The phone never writes the agent's saved slot: a choice travels as
 * `model_slot_override` on the chat body, which the server reads per request
 * (runtime/builder.py:454) and stores nowhere. So the only question here is
 * which slots are worth offering, and that answer must match the desktop or the
 * phone offers a model the agent would then fail to call.
 */
import { ModelInfo, ModelSlot, ProviderInfo } from './Dtos';
import { Parts } from './Parts';

/** One offerable (provider, model) pair, flattened so the menu is a single list. */
export class ModelOption {
  providerId: string = '';
  providerName: string = '';
  modelId: string = '';
  modelName: string = '';

  slot(): ModelSlot {
    const slot = new ModelSlot();
    slot.provider_id = this.providerId;
    slot.model = this.modelId;
    return slot;
  }
}

/** Providers as parsed out of JSON carry nulls where arrays were declared. */
function modelList(value: ModelInfo[] | undefined | null): ModelInfo[] {
  return value === undefined || value === null ? [] : value;
}

export class Providers {
  /**
   * Rebuild a parsed response as real instances. JSON.parse hands back plain
   * objects, and every field below is read assuming the declared shape.
   */
  static normalize(raw: ProviderInfo[]): ProviderInfo[] {
    const out: ProviderInfo[] = [];
    for (const item of raw) {
      const provider = new ProviderInfo();
      provider.id = Parts.str(item.id);
      provider.name = Parts.str(item.name);
      provider.base_url = Parts.str(item.base_url);
      provider.api_key = Parts.str(item.api_key);
      provider.models = modelList(item.models);
      provider.extra_models = modelList(item.extra_models);
      provider.is_free_tier = providerFlag(item.is_free_tier);
      provider.is_custom = providerFlag(item.is_custom);
      provider.is_local = providerFlag(item.is_local);
      // Absent means required, exactly like the console's `?? true`.
      provider.require_api_key = item.require_api_key !== false;
      if (provider.id.length > 0) {
        out.push(provider);
      }
    }
    return out;
  }

  /**
   * A provider is offerable when it has models and the credential it demands is
   * present; a free tier is always offerable, and a custom or no-key provider is
   * judged on its base_url instead of a key.
   */
  static eligible(provider: ProviderInfo): boolean {
    const hasModels = provider.models.length + provider.extra_models.length > 0;
    if (provider.id === 'hub-managed') {
      return hasModels;
    }
    if (provider.is_free_tier) {
      return true;
    }
    if (!hasModels) {
      return false;
    }
    if (provider.require_api_key === false) {
      return provider.base_url.length > 0;
    }
    if (provider.is_custom) {
      return provider.base_url.length > 0;
    }
    return provider.api_key.length > 0;
  }

  /** `models` first then `extra_models`, the same order the console flattens in. */
  static options(list: ProviderInfo[]): ModelOption[] {
    const out: ModelOption[] = [];
    for (const provider of list) {
      if (!Providers.eligible(provider)) {
        continue;
      }
      const merged: ModelInfo[] = [];
      for (const m of provider.models) {
        merged.push(m);
      }
      for (const m of provider.extra_models) {
        merged.push(m);
      }
      for (const m of merged) {
        const id = Parts.str(m.id);
        if (id.length === 0) {
          continue;
        }
        const option = new ModelOption();
        option.providerId = provider.id;
        option.providerName = provider.name.length > 0 ? provider.name : provider.id;
        option.modelId = id;
        option.modelName = Parts.str(m.name).length > 0 ? Parts.str(m.name) : id;
        out.push(option);
      }
    }
    return out;
  }

  /** The name the console would show for a slot: display name, else model id. */
  static displayName(options: ModelOption[], slot: ModelSlot | undefined): string {
    if (slot === undefined) {
      return '';
    }
    const providerId = Parts.str(slot.provider_id);
    const modelId = Parts.str(slot.model);
    if (providerId.length === 0 || modelId.length === 0) {
      return '';
    }
    for (const option of options) {
      if (option.providerId === providerId && option.modelId === modelId) {
        return option.modelName;
      }
    }
    // A slot the picker does not list is still worth naming: the server answered
    // with it, and an id beats silently claiming the agent has no model.
    return modelId;
  }
}

function providerFlag(value: boolean | undefined | null): boolean {
  return value === true;
}
