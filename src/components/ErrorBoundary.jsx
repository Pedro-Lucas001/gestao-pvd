import { Component } from "react";
import { reportError } from "../lib/monitoring";
export default class ErrorBoundary extends Component {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch(error) {
    reportError(error, this.props.area || "application");
  }
  render() {
    return this.state.failed ? (
      <section className="error-panel" role="alert">
        <h2>Esta área precisa ser recarregada.</h2>
        <p>
          As outras áreas continuam disponíveis. O pedido em rascunho permanece
          neste terminal.
        </p>
        <button
          className="secondary"
          onClick={() => this.setState({ failed: false })}
        >
          Tentar recuperar
        </button>
      </section>
    ) : (
      this.props.children
    );
  }
}
