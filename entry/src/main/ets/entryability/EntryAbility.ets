import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 初始化持久化存储：账户凭据（cookies）
    // 需在组件使用 AppStorage 之前调用


    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
    let isKeepScreenOn: boolean = true;
    try {
      window.getLastWindow(this.context, (err: BusinessError, data) => {
        const errCode: number = err.code;
        if (errCode) {
          console.error(`Failed to obtain the top window. Cause code: ${err.code}, message: ${err.message}`);
          return;
        }
        console.info(`Succeeded in obtaining the top window. Window id: ${data.getWindowProperties().id}`);
        data.setWindowKeepScreenOn(isKeepScreenOn, (err: BusinessError) => {
          const errCode: number = err.code;
          if (errCode) {
            console.error('Failed to set the screen to be always on. Cause: ' + JSON.stringify(err));
            return;
          }
          console.info('Succeeded in setting the screen to be always on.');
        });
      });
    } catch (exception) {
      console.error('Failed to set the screen to be always on. Cause: ' + JSON.stringify(exception));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    let context: common.UIAbilityContext = this.context;
    AppStorage.setOrCreate("UiAbilityContext", context);
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
