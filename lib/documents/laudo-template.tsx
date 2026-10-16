import { Document, Page, Text, View, StyleSheet, Font } from "@react-pdf/renderer";

// Estilos do documento
const styles = StyleSheet.create({
  page: {
    padding: 40,
    fontSize: 11,
    fontFamily: "Helvetica",
  },
  header: {
    marginBottom: 20,
    borderBottomWidth: 2,
    borderBottomColor: "#000",
    paddingBottom: 10,
  },
  title: {
    fontSize: 18,
    fontWeight: "bold",
    marginBottom: 5,
  },
  subtitle: {
    fontSize: 10,
    color: "#666",
  },
  section: {
    marginTop: 15,
    marginBottom: 10,
  },
  sectionTitle: {
    fontSize: 13,
    fontWeight: "bold",
    marginBottom: 8,
    backgroundColor: "#f0f0f0",
    padding: 5,
  },
  label: {
    fontSize: 10,
    fontWeight: "bold",
    color: "#333",
    marginTop: 5,
  },
  text: {
    fontSize: 11,
    marginBottom: 3,
    lineHeight: 1.4,
  },
  record: {
    marginTop: 10,
    padding: 10,
    backgroundColor: "#f9f9f9",
    borderLeftWidth: 3,
    borderLeftColor: "#000",
  },
  recordClient: {
    borderLeftColor: "#3b82f6",
  },
  recordWorker: {
    borderLeftColor: "#1f2937",
  },
  recordHeader: {
    fontSize: 10,
    fontWeight: "bold",
    marginBottom: 5,
  },
  recordDate: {
    fontSize: 9,
    color: "#666",
    marginBottom: 5,
  },
  footer: {
    position: "absolute",
    bottom: 30,
    left: 40,
    right: 40,
    textAlign: "center",
    fontSize: 9,
    color: "#666",
    borderTopWidth: 1,
    borderTopColor: "#ccc",
    paddingTop: 10,
  },
});

type LaudoData = {
  serviceNumber: number;
  serviceType: string;
  address: string;
  createdAt: string;
  completedAt: string | null;
  clientName: string;
  workerName: string;
  records: Array<{
    authorRole: "client" | "worker";
    content: string;
    createdAt: string;
  }>;
};

export function LaudoPDF({ data }: { data: LaudoData }) {
  return (
    <Document>
      <Page size="A4" style={styles.page}>
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.title}>
            LAUDO DE SERVIÇO #{String(data.serviceNumber).padStart(3, "0")}
          </Text>
          <Text style={styles.subtitle}>
            Documento gerado em {new Date().toLocaleDateString("pt-BR")} às{" "}
            {new Date().toLocaleTimeString("pt-BR")}
          </Text>
        </View>

        {/* Identificação */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>IDENTIFICAÇÃO</Text>
          <Text style={styles.text}>
            <Text style={styles.label}>Tipo de serviço: </Text>
            {data.serviceType}
          </Text>
          <Text style={styles.text}>
            <Text style={styles.label}>Endereço: </Text>
            {data.address}
          </Text>
          <Text style={styles.text}>
            <Text style={styles.label}>Data de criação: </Text>
            {new Date(data.createdAt).toLocaleDateString("pt-BR")}
          </Text>
          {data.completedAt && (
            <Text style={styles.text}>
              <Text style={styles.label}>Data de conclusão: </Text>
              {new Date(data.completedAt).toLocaleDateString("pt-BR")}
            </Text>
          )}
        </View>

        {/* Participantes */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>PARTICIPANTES</Text>
          <Text style={styles.text}>
            <Text style={styles.label}>Cliente: </Text>
            {data.clientName}
          </Text>
          <Text style={styles.text}>
            <Text style={styles.label}>Trabalhador: </Text>
            {data.workerName}
          </Text>
        </View>

        {/* Registros */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>REGISTROS DO SERVIÇO</Text>
          {data.records.length === 0 ? (
            <Text style={styles.text}>Nenhum registro disponível.</Text>
          ) : (
            data.records.map((record, index) => (
              <View
                key={index}
                style={[
                  styles.record,
                  record.authorRole === "client"
                    ? styles.recordClient
                    : styles.recordWorker,
                ]}
              >
                <Text style={styles.recordHeader}>
                  {record.authorRole === "client"
                    ? "Registro do Cliente"
                    : "Registro do Trabalhador"}
                </Text>
                <Text style={styles.recordDate}>
                  {new Date(record.createdAt).toLocaleDateString("pt-BR")} às{" "}
                  {new Date(record.createdAt).toLocaleTimeString("pt-BR")}
                </Text>
                <Text style={styles.text}>{record.content}</Text>
              </View>
            ))
          )}
        </View>

        {/* Footer */}
        <View style={styles.footer}>
          <Text>
            Este documento foi gerado automaticamente pelo sistema souza.l.
          </Text>
          <Text>
            As informações aqui contidas foram registradas pelas partes durante
            a execução do serviço.
          </Text>
        </View>
      </Page>
    </Document>
  );
}
