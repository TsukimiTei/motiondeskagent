import { useState, useEffect, useCallback } from 'react';
import { stateMachine, CharacterState, StateTransitionEvent } from '../stateMachine';
import { bridge } from '../bridge';

export function useStateMachine() {
  const [state, setState] = useState<CharacterState>(stateMachine.getState());

  useEffect(() => {
    const unsub = stateMachine.onStateChange((newState) => {
      setState(newState);
      bridge.send('stateChange', { state: newState });
    });
    return unsub;
  }, []);

  const dispatch = useCallback((event: StateTransitionEvent) => {
    return stateMachine.dispatch(event);
  }, []);

  const isInteractive = ['listening', 'thinking', 'speaking', 'tool-executing'].includes(state);

  return { state, dispatch, isInteractive };
}
